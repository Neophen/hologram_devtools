/**
 * HoloDev Bridge Script
 *
 * Injected into Hologram pages in dev mode. Connects to the HoloDev server
 * via WebSocket and provides live component state snapshots, action tracking,
 * and state editing capabilities.
 */
(function () {
  "use strict";

  const BRIDGE_URL = `ws://${location.hostname || "localhost"}:4008/bridge`;
  const RECONNECT_INTERVAL = 3000;
  const MAX_RECONNECT_ATTEMPTS = 20;

  let ws = null;
  let reconnectAttempts = 0;
  let reconnectTimer = null;
  let hooked = false;

  // Detection flag for extensions
  window.__HOLOGRAM_DEVTOOLS__ = { detected: false, version: null, bridge: null };

  // --- Type Unboxing (Hologram Type -> typed JSON) ---

  function unbox(term) {
    if (term === undefined || term === null) {
      return { _t: "nil", v: null };
    }

    if (typeof term !== "object") {
      // Primitive JS values (shouldn't normally appear in Hologram state)
      return { _t: typeof term, v: term };
    }

    const type = term.type;

    switch (type) {
      case "atom":
        if (term.value === "nil") return { _t: "nil", v: null };
        if (term.value === "true") return { _t: "boolean", v: true };
        if (term.value === "false") return { _t: "boolean", v: false };
        return { _t: "atom", v: term.value };

      case "integer":
        return { _t: "integer", v: Number(term.value) };

      case "float":
        return { _t: "float", v: term.value };

      case "bitstring": {
        // Extract text from bitstring segments
        const text =
          term.segments && term.segments.length > 0
            ? term.segments.map((s) => s.value).join("")
            : "";
        return { _t: "string", v: text };
      }

      case "list": {
        const items = term.data ? term.data.map(unbox) : [];
        return { _t: "list", v: items };
      }

      case "tuple": {
        const items = term.data ? term.data.map(unbox) : [];
        return { _t: "tuple", v: items };
      }

      case "map": {
        if (term.data) {
          // Check if it's a struct
          const structKey = Object.keys(term.data).find((k) => {
            const entry = term.data[k];
            return (
              entry &&
              entry[0] &&
              entry[0].type === "atom" &&
              entry[0].value === "__struct__"
            );
          });

          if (structKey) {
            const structModule = term.data[structKey][1];
            const structName = structModule.value || String(structModule);
            const fields = {};

            for (const key of Object.keys(term.data)) {
              if (key === structKey) continue;
              const [k, v] = term.data[key];
              const unboxedKey = unbox(k);
              const fieldName =
                unboxedKey._t === "atom" ? unboxedKey.v : JSON.stringify(unboxedKey);
              fields[fieldName] = unbox(v);
            }

            return { _t: "struct", module: structName, v: fields };
          }

          // Regular map
          const entries = {};
          for (const key of Object.keys(term.data)) {
            const [k, v] = term.data[key];
            const unboxedKey = unbox(k);
            const mapKey =
              unboxedKey._t === "atom" ? unboxedKey.v : JSON.stringify(unboxedKey);
            entries[mapKey] = unbox(v);
          }
          return { _t: "map", v: entries };
        }
        return { _t: "map", v: {} };
      }

      case "pid":
        return { _t: "pid", v: term.segments ? term.segments.join(".") : "?" };

      case "anonymous_function":
        return { _t: "function", v: "#Function" };

      default:
        // Unknown type - try to serialize
        try {
          return { _t: "unknown", v: JSON.parse(JSON.stringify(term)) };
        } catch {
          return { _t: "unknown", v: String(term) };
        }
    }
  }

  // --- Type Reboxing (typed JSON -> Hologram Type) ---

  function rebox(typed) {
    if (!typed || typeof typed !== "object" || !typed._t) {
      return globalThis.Hologram.deps.Type.atom("nil");
    }

    const Type = globalThis.Hologram.deps.Type;

    switch (typed._t) {
      case "nil":
        return Type.atom("nil");

      case "boolean":
        return Type.atom(typed.v ? "true" : "false");

      case "atom":
        return Type.atom(typed.v);

      case "integer":
        return Type.integer(BigInt(typed.v));

      case "float":
        return Type.float(typed.v);

      case "string":
        return Type.bitstring(typed.v);

      case "list":
        return Type.list(typed.v.map(rebox));

      case "tuple":
        return Type.tuple(typed.v.map(rebox));

      case "map": {
        const data = {};
        for (const [key, val] of Object.entries(typed.v)) {
          const boxedKey = Type.atom(key);
          const encodedKey = Type.encodeMapKey(boxedKey);
          data[encodedKey] = [boxedKey, rebox(val)];
        }
        return { type: "map", data };
      }

      case "struct": {
        const data = {};
        // Add __struct__ key
        const structAtom = Type.atom("__struct__");
        const structVal = Type.atom(typed.module);
        const structEnc = Type.encodeMapKey(structAtom);
        data[structEnc] = [structAtom, structVal];

        for (const [key, val] of Object.entries(typed.v)) {
          const boxedKey = Type.atom(key);
          const encodedKey = Type.encodeMapKey(boxedKey);
          data[encodedKey] = [boxedKey, rebox(val)];
        }
        return { type: "map", data };
      }

      default:
        return Type.atom("nil");
    }
  }

  // --- Registry Snapshot ---

  function snapshotRegistry() {
    try {
      const registry = globalThis.Hologram.deps.ComponentRegistry;
      if (!registry || !registry.entries || !registry.entries.data) {
        return null;
      }

      const entries = registry.entries.data;
      const components = {};
      let page = null;

      for (const key of Object.keys(entries)) {
        const [cidTerm, entryTerm] = entries[key];
        const cid = cidTerm.type === "bitstring"
          ? cidTerm.segments.map((s) => s.value).join("")
          : String(cidTerm.value || cidTerm);

        const moduleTerm = entryTerm.data
          ? Object.values(entryTerm.data).find(
              ([k]) => k.type === "atom" && k.value === "module"
            )
          : null;

        const structTerm = entryTerm.data
          ? Object.values(entryTerm.data).find(
              ([k]) => k.type === "atom" && k.value === "struct"
            )
          : null;

        const moduleName = moduleTerm ? String(moduleTerm[1].value || moduleTerm[1]) : "unknown";

        // Extract state from the component struct
        let state = {};
        let emittedContext = {};

        if (structTerm && structTerm[1] && structTerm[1].data) {
          const structData = structTerm[1].data;

          // Find state field
          const stateEntry = Object.values(structData).find(
            ([k]) => k.type === "atom" && k.value === "state"
          );
          if (stateEntry && stateEntry[1] && stateEntry[1].data) {
            state = unboxMap(stateEntry[1]);
          }

          // Find emitted_context field
          const ctxEntry = Object.values(structData).find(
            ([k]) => k.type === "atom" && k.value === "emitted_context"
          );
          if (ctxEntry && ctxEntry[1] && ctxEntry[1].data) {
            emittedContext = unboxMap(ctxEntry[1]);
          }
        }

        const component = {
          cid,
          module: moduleName,
          state,
          emitted_context: emittedContext,
        };

        if (cid === "page") {
          page = component;
        } else {
          components[cid] = component;
        }
      }

      return {
        page,
        components,
        timestamp: Date.now(),
      };
    } catch (e) {
      console.warn("[HoloDev Bridge] Snapshot failed:", e);
      return null;
    }
  }

  function unboxMap(mapTerm) {
    const result = {};
    if (!mapTerm || !mapTerm.data) return result;

    for (const key of Object.keys(mapTerm.data)) {
      const [k, v] = mapTerm.data[key];
      const unboxedKey = unbox(k);
      const fieldName =
        unboxedKey._t === "atom" ? unboxedKey.v : JSON.stringify(unboxedKey);
      result[fieldName] = unbox(v);
    }
    return result;
  }

  // --- State Editing ---

  function editState(cid, path, typedValue) {
    try {
      const registry = globalThis.Hologram.deps.ComponentRegistry;
      const Erlang_Maps = globalThis.Hologram.deps.Erlang_Maps;
      const Type = globalThis.Hologram.deps.Type;

      // Get current component struct
      const componentStruct = registry.getComponentStruct(
        Type.bitstring(cid)
      );
      if (!componentStruct) {
        console.warn("[HoloDev Bridge] Component not found:", cid);
        return false;
      }

      // Get current state map from struct
      let stateMap = Erlang_Maps["get/2"](Type.atom("state"), componentStruct);

      // Navigate path and set value
      const reboxedValue = rebox(typedValue);

      if (path.length === 1) {
        stateMap = Erlang_Maps["put/3"](
          Type.atom(path[0]),
          reboxedValue,
          stateMap
        );
      } else {
        // Deep path - navigate to parent, then set
        stateMap = deepPut(stateMap, path, reboxedValue, Type, Erlang_Maps);
      }

      // Build new component struct with updated state
      const newStruct = Erlang_Maps["put/3"](
        Type.atom("state"),
        stateMap,
        componentStruct
      );

      // Update registry and re-render
      registry.putComponentStruct(Type.bitstring(cid), newStruct);
      globalThis.Hologram.render();

      return true;
    } catch (e) {
      console.error("[HoloDev Bridge] Edit failed:", e);
      return false;
    }
  }

  function deepPut(map, path, value, Type, Erlang_Maps) {
    if (path.length === 1) {
      return Erlang_Maps["put/3"](Type.atom(path[0]), value, map);
    }

    const [head, ...rest] = path;
    const key = Type.atom(head);
    const child = Erlang_Maps["get/2"](key, map);
    const updatedChild = deepPut(child, rest, value, Type, Erlang_Maps);
    return Erlang_Maps["put/3"](key, updatedChild, map);
  }

  // --- Action Tracking ---

  const actionHistory = [];
  const MAX_ACTION_HISTORY = 200;

  function trackAction(name, target, params, duration) {
    const entry = {
      name: String(name.value || name),
      target: String(
        target.type === "bitstring"
          ? target.segments.map((s) => s.value).join("")
          : target.value || target
      ),
      params: unbox(params),
      duration,
      timestamp: Date.now(),
    };

    actionHistory.push(entry);
    if (actionHistory.length > MAX_ACTION_HISTORY) {
      actionHistory.shift();
    }

    // Send to server
    send({ type: "action", data: entry });
  }

  // --- Hologram Hooks ---

  function hookIntoHologram() {
    if (hooked) return;

    const Hologram = globalThis.Hologram;
    if (!Hologram) return;

    // Hook render() to send snapshots after each render
    const originalRender = Hologram.render.bind(Hologram);
    Hologram.render = function () {
      const result = originalRender();

      // Send snapshot after render completes
      setTimeout(() => {
        const snapshot = snapshotRegistry();
        if (snapshot) {
          send({ type: "snapshot", data: snapshot });
        }
      }, 0);

      return result;
    };

    // Hook executeAction() to track actions
    const originalExecuteAction = Hologram.executeAction.bind(Hologram);
    Hologram.executeAction = function (action) {
      const startTime = performance.now();
      const Type = Hologram.deps.Type;
      const Erlang_Maps = Hologram.deps.Erlang_Maps;

      const name = Erlang_Maps["get/2"](Type.atom("name"), action);
      const params = Erlang_Maps["get/2"](Type.atom("params"), action);
      const target = Erlang_Maps["get/2"](Type.atom("target"), action);

      const result = originalExecuteAction(action);

      // Track after execution (use setTimeout to capture duration after async)
      const duration = performance.now() - startTime;
      trackAction(name, target, params, duration);

      return result;
    };

    hooked = true;
    console.log("[HoloDev Bridge] Hooks installed");
  }

  // --- WebSocket Connection ---

  function connect() {
    if (ws && ws.readyState <= 1) return; // CONNECTING or OPEN

    try {
      ws = new WebSocket(BRIDGE_URL);
    } catch {
      scheduleReconnect();
      return;
    }

    ws.onopen = function () {
      console.log("[HoloDev Bridge] Connected to", BRIDGE_URL);
      reconnectAttempts = 0;
      window.__HOLOGRAM_DEVTOOLS__.bridge = "connected";

      send({ type: "mounted" });

      // Send initial snapshot
      const snapshot = snapshotRegistry();
      if (snapshot) {
        send({ type: "snapshot", data: snapshot });
      }
    };

    ws.onmessage = function (event) {
      try {
        const msg = JSON.parse(event.data);
        handleServerMessage(msg);
      } catch (e) {
        console.warn("[HoloDev Bridge] Invalid message:", e);
      }
    };

    ws.onclose = function () {
      window.__HOLOGRAM_DEVTOOLS__.bridge = "disconnected";
      scheduleReconnect();
    };

    ws.onerror = function () {
      // onclose will fire after this
    };
  }

  function scheduleReconnect() {
    if (reconnectTimer) return;
    if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
      console.log("[HoloDev Bridge] Max reconnect attempts reached");
      return;
    }

    reconnectAttempts++;
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connect();
    }, RECONNECT_INTERVAL);
  }

  function send(msg) {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(msg));
    }
  }

  function handleServerMessage(msg) {
    switch (msg.type) {
      case "edit_state":
        editState(msg.cid, msg.path, msg.value);
        break;

      case "dispatch_action": {
        const Hologram = globalThis.Hologram;
        if (Hologram && Hologram.dispatchAction) {
          const Type = Hologram.deps.Type;
          // Build action params
          const params = msg.params || {};
          const boxedParams = rebox({ _t: "map", v: params });
          Hologram.dispatchAction(msg.target, msg.name, boxedParams);
        }
        break;
      }

      case "ping":
        send({ type: "pong" });
        break;

      default:
        console.log("[HoloDev Bridge] Unknown message type:", msg.type);
    }
  }

  // --- Initialization ---

  function init() {
    // Wait for Hologram to be available
    const checkInterval = setInterval(() => {
      if (globalThis.Hologram && globalThis.Hologram.deps) {
        clearInterval(checkInterval);

        window.__HOLOGRAM_DEVTOOLS__.detected = true;
        window.__HOLOGRAM_DEVTOOLS__.version = "0.4";

        hookIntoHologram();
        connect();

        console.log("[HoloDev Bridge] Hologram detected, bridge initialized");
      }
    }, 100);

    // Give up after 30 seconds
    setTimeout(() => clearInterval(checkInterval), 30000);
  }

  // Start when DOM is ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
