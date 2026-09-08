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
 *     zoomTo / fitToScreen / setMode / elementCount, et depuis le lot 17
 *     setLibrary / insertShape / getSelection / select / moveElements /
 *     setSelectionKind / insertImage / setPressure ;
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
  // Mode Schéma : un connecteur est une flèche, à ceci près que la liaison
  // (`startBinding`/`endBinding`) est active — cf. MODE_DEFAULTS.diagram.
  connector: "arrow",
  // Mode Manuscrit. `ruler` est le trait droit d'Excalidraw (⇧ le contraint à
  // l'horizontale ou à la verticale) ; `lasso` retombe sur la sélection
  // rectangulaire — Excalidraw 0.18.1 n'a pas d'outil lasso.
  pen: "freedraw",
  highlighter: "freedraw",
  ruler: "line",
  lasso: "selection",
};

// Clé d'annotation dans `customData` — miroir de
// `BoardAnnotation.customDataKey`.
const KIND_KEY = "one2oneKind";

// Réglages du surligneur : large et translucide (spec §7.1, « surligneur »).
const HIGHLIGHTER = { opacity: 40, strokeWidth: 8 };

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
    // Connecteurs liés et magnétisme : une flèche posée sur une forme la suit
    // quand on la déplace, et les formes s'alignent entre elles (spec §7.1 :
    // « connecteurs magnétisés, points d'ancrage »).
    isBindingEnabled: true,
    objectsSnapModeEnabled: true,
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

/// Reporte sur le dernier tracé `freedraw` les pressions relevées côté natif.
///
/// Pourquoi ce détour : dans un `WKWebView`, les `PointerEvent` de macOS
/// n'apportent pas la pression d'une tablette, et le moteur retombe alors sur
/// `simulatePressure` (qui déduit l'épaisseur de la vitesse). Le côté Swift
/// (`StylusPressureMonitor`) lit la vraie pression dans les `NSEvent` et
/// l'envoie ici par `setPressure` pendant le geste ; à la levée du stylet, on
/// rééchantillonne la série sur les points du tracé et on désarme la
/// simulation.
function applyPressures(api, samples) {
  if (!samples || samples.length < 2) return 0;
  const elements = api.getSceneElements();
  let cible = null;
  for (let i = elements.length - 1; i >= 0; i -= 1) {
    if (elements[i].type === "freedraw") {
      cible = elements[i];
      break;
    }
  }
  if (!cible || !cible.points || cible.points.length < 2) return 0;

  const n = cible.points.length;
  const pressures = new Array(n);
  for (let i = 0; i < n; i += 1) {
    const t = (i * (samples.length - 1)) / (n - 1);
    const bas = Math.floor(t);
    const haut = Math.min(samples.length - 1, bas + 1);
    const frac = t - bas;
    pressures[i] = samples[bas] * (1 - frac) + samples[haut] * frac;
  }

  api.updateScene({
    elements: elements.map((element) =>
      element.id === cible.id
        ? {
            ...element,
            pressures,
            simulatePressure: false,
            version: (element.version || 1) + 1,
          }
        : element
    ),
    // Le tracé a déjà son entrée d'historique : en ajouter une seconde
    // demanderait deux `↺` pour effacer un seul trait.
    captureUpdate: "NEVER",
  });
  return n;
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
  // Pression du stylet : la valeur courante poussée par Swift, et la série
  // relevée pendant le geste en cours.
  const pressureRef = useRef({ current: null, samples: [], recording: false });

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
    const pression = pressureRef.current;
    window.oneToOneBoard = makeBridge(api, syncGrid, pression);
    post({ type: "ready" });

    // Un geste = une série de pressions. On n'enregistre que si le natif a
    // annoncé une pression : à la souris, `simulatePressure` reste en place.
    const arreteDown = api.onPointerDown(() => {
      pression.recording = pression.current !== null;
      pression.samples = pression.recording ? [pression.current] : [];
    });
    const arreteUp = api.onPointerUp(() => {
      if (pression.recording) applyPressures(api, pression.samples);
      pression.recording = false;
      pression.samples = [];
    });

    return () => {
      if (typeof arreteDown === "function") arreteDown();
      if (typeof arreteUp === "function") arreteUp();
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

function makeBridge(api, syncGrid, pressure) {
  const container = () => document.querySelector(".excalidraw") || document.body;

  const parse = (valeur, defaut) =>
    typeof valeur === "string" ? JSON.parse(valeur || defaut) : valeur || JSON.parse(defaut);

  const selectedIDs = () => {
    const carte = api.getAppState().selectedElementIds || {};
    return api
      .getSceneElements()
      .filter((element) => carte[element.id])
      .map((element) => element.id);
  };

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
      } else if (name === "highlighter") {
        api.updateScene({
          appState: {
            currentItemOpacity: HIGHLIGHTER.opacity,
            currentItemStrokeWidth: HIGHLIGHTER.strokeWidth,
            currentItemRoughness: 0,
          },
        });
      } else if (name === "pen" || name === "pencil") {
        // Sortir du surligneur rend l'opacité pleine : sinon le trait suivant
        // resterait translucide sans que rien ne le dise.
        api.updateScene({ appState: { currentItemOpacity: 100 } });
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

    // --- Lot 17 : bibliothèque, alignement, annotations, images, pression ---

    async setLibrary(json) {
      const fichier = parse(json, "{}");
      const items = fichier.libraryItems || [];
      await api.updateLibrary({
        libraryItems: items,
        // Remplace : la bibliothèque est celle de l'application, elle ne
        // s'accumule pas au fil des chargements de planche.
        merge: false,
        openLibraryMenu: false,
        defaultStatus: "published",
      });
      return items.length;
    },

    insertShape(json) {
      const ajouts = parse(json, "[]");
      if (!ajouts.length) return 0;
      const selection = {};
      ajouts.forEach((element) => {
        selection[element.id] = true;
      });
      api.updateScene({
        elements: api.getSceneElements().concat(ajouts),
        // Déposée sélectionnée : on la déplace tout de suite, sans re-cliquer.
        appState: { selectedElementIds: selection },
        captureUpdate: "IMMEDIATELY",
      });
      return ajouts.length;
    },

    getSelection() {
      return selectedIDs();
    },

    select(ids) {
      const carte = {};
      (ids || []).forEach((id) => {
        carte[id] = true;
      });
      api.updateScene({ appState: { selectedElementIds: carte } });
      return Object.keys(carte).length;
    },

    moveElements(json) {
      const positions = parse(json, "{}");
      const clefs = Object.keys(positions);
      if (!clefs.length) return 0;
      api.updateScene({
        elements: api.getSceneElements().map((element) => {
          const cible = positions[element.id];
          if (!cible) return element;
          return {
            ...element,
            x: cible.x,
            y: cible.y,
            version: (element.version || 1) + 1,
          };
        }),
        // Capturé dans l'historique : `↺` défait un alignement comme
        // n'importe quel geste.
        captureUpdate: "IMMEDIATELY",
      });
      return clefs.length;
    },

    setSelectionKind(kind) {
      const carte = api.getAppState().selectedElementIds || {};
      let touches = 0;
      const elements = api.getSceneElements().map((element) => {
        if (!carte[element.id]) return element;
        touches += 1;
        const custom = { ...(element.customData || {}) };
        if (kind) custom[KIND_KEY] = kind;
        else delete custom[KIND_KEY];
        return { ...element, customData: custom, version: (element.version || 1) + 1 };
      });
      if (touches === 0) return 0;
      api.updateScene({ elements, captureUpdate: "IMMEDIATELY" });
      return touches;
    },

    async insertImage(dataURL, fileId, elementJSON) {
      // La donnée entre dans la scène ; **aucun chemin de disque** n'y figure
      // (spec §8 : copie, jamais référence).
      api.addFiles([
        { id: fileId, dataURL, mimeType: "image/png", created: Date.now() },
      ]);
      const ajouts = parse(elementJSON, "[]");
      if (!ajouts.length) return null;

      // L'élément vient de Swift avec un décalage constant : on le repose au
      // coin haut-gauche de la vue courante, sinon une planche panoramiquée
      // recevrait son image hors écran.
      const etat = api.getAppState();
      const zoom = (etat.zoom && etat.zoom.value) || 1;
      const dx = -(etat.scrollX || 0);
      const dy = -(etat.scrollY || 0);
      const places = ajouts.map((element) => ({
        ...element,
        x: dx + element.x / zoom,
        y: dy + element.y / zoom,
      }));

      api.updateScene({
        elements: api.getSceneElements().concat(places),
        captureUpdate: "IMMEDIATELY",
      });
      return fileId;
    },

    setPressure(value) {
      // -1 vaut « aucune pression » (`callAsyncJavaScript` n'accepte pas null).
      const valeur = typeof value === "number" && value >= 0 ? value : null;
      pressure.current = valeur;
      if (pressure.recording && valeur !== null) pressure.samples.push(valeur);
      return valeur;
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
