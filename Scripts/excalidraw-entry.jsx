/*
 * Point d'entrée du bundle Excalidraw embarqué (Atelier — moteur de planches).
 *
 * Construit par `Scripts/build-excalidraw-bundle.sh` en un seul fichier IIFE
 * (`OneToOne/Resources/Whiteboard/excalidraw.bundle.js`), inliné dans la page
 * par `WhiteboardHTML.page()`.
 *
 * Contrat avec Swift (`WhiteboardBridge`) :
 *   - `window.oneToOneBoard` expose load / getScene / exportPNG / exportSVG /
 *     exportThumbnail / setTool / setColor / setStrokeWidth / undo / redo /
 *     zoomTo / fitToScreen / setMode / elementCount ;
 *   - la page poste `{type:"ready"}` puis `{type:"change", …}` (debounce 400 ms)
 *     sur `window.webkit.messageHandlers.board`.
 *
 * L'interface d'Excalidraw est masquée (`.layer-ui__wrapper`) : toute la chrome
 * — barre d'outils, palette, dock — est native (SwiftUI), conformément à
 * l'écran `6a-atelier-planche.png`.
 */

import React, { useCallback, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Excalidraw, exportToBlob, exportToSvg } from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";

// --- Pont vers Swift --------------------------------------------------------

function post(payload) {
  try {
    window.webkit.messageHandlers.board.postMessage(payload);
  } catch (error) {
    // Hors WKWebView (mise au point dans un navigateur) : on ignore.
  }
}

// --- Correspondances outil / mode ------------------------------------------

// Les noms de gauche sont ceux de la palette verticale de l'écran 6a ;
// `note` est un rectangle préréglé en jaune post-it.
const TOOL_TYPES = {
  pencil: "freedraw",
  rectangle: "rectangle",
  ellipse: "ellipse",
  arrow: "arrow",
  line: "line",
  text: "text",
  image: "image",
  note: "rectangle",
  frame: "frame",
  eraser: "eraser",
  selection: "selection",
  hand: "hand",
};

// FONT_FAMILY d'Excalidraw : 5 = Excalifont (tracé main levée), 6 = Nunito.
const FONT_HAND = 5;
const FONT_NEAT = 6;

const MODE_DEFAULTS = {
  sketch: {
    currentItemRoughness: 1,
    currentItemFontFamily: FONT_HAND,
    currentItemStrokeStyle: "solid",
    currentItemFillStyle: "hachure",
    currentItemEdges: "sharp",
  },
  diagram: {
    currentItemRoughness: 0,
    currentItemFontFamily: FONT_NEAT,
    currentItemStrokeStyle: "solid",
    currentItemFillStyle: "solid",
    currentItemEdges: "round",
    currentItemArrowType: "round",
  },
  ink: {
    currentItemRoughness: 1,
    currentItemFontFamily: FONT_HAND,
    currentItemStrokeStyle: "solid",
    currentItemFillStyle: "hachure",
    currentItemEdges: "sharp",
  },
};

const DEFAULT_APP_STATE = {
  viewBackgroundColor: "transparent",
  currentItemStrokeColor: "#1a1a1a",
  currentItemBackgroundColor: "transparent",
  currentItemStrokeWidth: 2,
  currentItemRoughness: 1,
  currentItemFontFamily: FONT_HAND,
  gridSize: null,
};

// --- Utilitaires ------------------------------------------------------------

async function blobToBase64(blob) {
  const buffer = await blob.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function sanitizedAppState(appState) {
  // Les champs de session (collaborateurs, curseurs, sélection) ne sont pas
  // persistés : la planche est mono-utilisateur (décision D11).
  const {
    collaborators,
    selectedElementIds,
    selectedGroupIds,
    editingTextElement,
    newElement,
    ...rest
  } = appState || {};
  return rest;
}

// --- Composant --------------------------------------------------------------

function BoardApp() {
  const [api, setApi] = useState(null);
  const apiRef = useRef(null);
  const debounceRef = useRef(null);
  const gridRef = useRef(null);

  apiRef.current = api;

  // La grille de points suit le panoramique et le zoom : Excalidraw peint un
  // fond transparent, les points viennent du CSS de `#board-grid`.
  const syncGrid = useCallback((appState) => {
    const node = gridRef.current;
    if (!node || !appState) return;
    const zoom = (appState.zoom && appState.zoom.value) || 1;
    const step = 18 * zoom;
    node.style.backgroundSize = `${step}px ${step}px`;
    node.style.backgroundPosition = `${(appState.scrollX || 0) * zoom}px ${(appState.scrollY || 0) * zoom}px`;
  }, []);

  const handleChange = useCallback(
    (elements, appState, files) => {
      syncGrid(appState);
      if (debounceRef.current) clearTimeout(debounceRef.current);
      debounceRef.current = setTimeout(() => {
        post({
          type: "change",
          scene: serializeScene(elements, appState, files),
          elementCount: elements.filter((element) => !element.isDeleted).length,
        });
      }, 400);
    },
    [syncGrid]
  );

  useEffect(() => {
    if (!api) return;
    window.oneToOneBoard = makeBridge(api, syncGrid);
    post({ type: "ready" });
    return () => {
      delete window.oneToOneBoard;
    };
  }, [api, syncGrid]);

  return (
    <div className="board-root">
      <div id="board-grid" ref={gridRef} />
      <Excalidraw
        excalidrawAPI={setApi}
        onChange={handleChange}
        initialData={{ elements: [], appState: DEFAULT_APP_STATE, scrollToContent: false }}
        detectScroll={false}
        handleKeyboardGlobally
        autoFocus
        UIOptions={{
          canvasActions: {
            changeViewBackgroundColor: false,
            clearCanvas: false,
            export: false,
            loadScene: false,
            saveToActiveFile: false,
            saveAsImage: false,
            toggleTheme: false,
          },
          tools: { image: true },
        }}
      />
    </div>
  );
}

function serializeScene(elements, appState, files) {
  return JSON.stringify({
    type: "excalidraw",
    version: 2,
    source: "OneToOne",
    elements: (elements || []).filter((element) => !element.isDeleted),
    appState: sanitizedAppState(appState),
    files: files || {},
  });
}

function makeBridge(api, syncGrid) {
  const container = () => document.querySelector(".excalidraw") || document.body;

  const exportArgs = (overrides) => ({
    elements: api.getSceneElements(),
    appState: {
      ...api.getAppState(),
      exportBackground: true,
      viewBackgroundColor: "#fdfcfa",
      exportWithDarkMode: false,
      exportEmbedScene: false,
      ...overrides,
    },
    files: api.getFiles(),
  });

  // Excalidraw n'expose pas `undo()`/`redo()` : on rejoue le raccourci clavier,
  // que son gestionnaire global (`handleKeyboardGlobally`) écoute sur le
  // document. La profondeur d'historique (100) est celle du moteur.
  const replayShortcut = (shiftKey) => {
    const event = new KeyboardEvent("keydown", {
      key: "z",
      code: "KeyZ",
      keyCode: 90,
      which: 90,
      metaKey: true,
      ctrlKey: false,
      shiftKey,
      bubbles: true,
      cancelable: true,
    });
    container().dispatchEvent(event);
    document.dispatchEvent(event);
  };

  return {
    version: 1,

    load(scene) {
      const parsed = typeof scene === "string" ? JSON.parse(scene || "{}") : scene || {};
      const elements = parsed.elements || [];
      if (parsed.files && Object.keys(parsed.files).length > 0) {
        api.addFiles(Object.values(parsed.files));
      }
      api.updateScene({
        elements,
        appState: { ...DEFAULT_APP_STATE, ...sanitizedAppState(parsed.appState) },
      });
      api.history.clear();
      syncGrid(api.getAppState());
      return elements.length;
    },

    getScene() {
      return serializeScene(api.getSceneElements(), api.getAppState(), api.getFiles());
    },

    elementCount() {
      return api.getSceneElements().length;
    },

    async exportPNG(maxWidthOrHeight) {
      const blob = await exportToBlob({
        ...exportArgs(),
        mimeType: "image/png",
        exportPadding: 24,
        ...(maxWidthOrHeight ? { maxWidthOrHeight } : {}),
      });
      return await blobToBase64(blob);
    },

    async exportThumbnail() {
      return await this.exportPNG(240);
    },

    async exportSVG() {
      const svg = await exportToSvg({ ...exportArgs(), exportPadding: 24 });
      return svg.outerHTML;
    },

    setTool(name) {
      const type = TOOL_TYPES[name] || "selection";
      if (name === "note") {
        api.updateScene({
          appState: {
            currentItemBackgroundColor: "#fef3c7",
            currentItemFillStyle: "solid",
            currentItemStrokeColor: "#8a5a12",
          },
        });
      }
      api.setActiveTool({ type });
      return type;
    },

    setColor(hex) {
      api.updateScene({ appState: { currentItemStrokeColor: hex } });
      return hex;
    },

    setStrokeWidth(width) {
      api.updateScene({ appState: { currentItemStrokeWidth: width } });
      return width;
    },

    undo() {
      replayShortcut(false);
    },

    redo() {
      replayShortcut(true);
    },

    zoomTo(percent) {
      const value = Math.min(4, Math.max(0.25, percent / 100));
      api.updateScene({ appState: { zoom: { value } } });
      syncGrid(api.getAppState());
      return Math.round(value * 100);
    },

    fitToScreen() {
      const elements = api.getSceneElements();
      if (elements.length === 0) {
        api.updateScene({ appState: { zoom: { value: 1 }, scrollX: 0, scrollY: 0 } });
      } else {
        api.scrollToContent(elements, { fitToViewport: true, viewportZoomFactor: 0.9 });
      }
      syncGrid(api.getAppState());
      return true;
    },

    setMode(mode) {
      const defaults = MODE_DEFAULTS[mode] || MODE_DEFAULTS.sketch;
      api.updateScene({ appState: defaults });
      api.setActiveTool({ type: mode === "diagram" ? "selection" : "freedraw" });
      return mode;
    },
  };
}

// --- Montage ----------------------------------------------------------------

const style = document.createElement("style");
style.textContent = `
  html, body, #root { margin: 0; height: 100%; width: 100%; overflow: hidden; background: #fdfcfa; }
  .board-root { position: absolute; inset: 0; }
  #board-grid {
    position: absolute; inset: 0; pointer-events: none; z-index: 0;
    background-color: #fdfcfa;
    background-image: radial-gradient(circle, rgba(0,0,0,0.14) 1px, transparent 1px);
    background-size: 18px 18px;
  }
  .board-root .excalidraw { position: absolute; inset: 0; background: transparent; }
  /* Toute la chrome est native (SwiftUI) : l'UI d'Excalidraw est masquée. */
  .board-root .excalidraw .layer-ui__wrapper { display: none !important; }
  .board-root .excalidraw .App-bottom-bar { display: none !important; }
`;
document.head.appendChild(style);

const host = document.getElementById("root") || document.body.appendChild(document.createElement("div"));
host.id = "root";
createRoot(host).render(<BoardApp />);
