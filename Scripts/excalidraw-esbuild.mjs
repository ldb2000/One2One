// Construction du bundle Excalidraw embarqué. Appelé par
// `Scripts/build-excalidraw-bundle.sh` depuis le dossier temporaire de travail.
//
// Deux allègements par rapport à un `esbuild --bundle` nu : Excalidraw importe
// dynamiquement 55 traductions et le convertisseur Mermaid → Excalidraw. En
// IIFE, esbuild **inline** tout ce qui est atteignable, ce qui portait le
// fichier à 8,5 Mo. Comme l'interface d'Excalidraw est masquée (toute la chrome
// est native, cf. `6a-atelier-planche.png`), ni les traductions ni la boîte de
// dialogue Mermaid ne sont accessibles : on les remplace par des modules vides.

import * as esbuild from "esbuild";

// Traductions conservées : l'anglais est la langue de repli du moteur, le
// français celle de l'application.
const KEPT_LOCALES = /\/locales\/(en|fr-FR)-[A-Z0-9]+\.js$/;

const trimPlugin = {
  name: "onetoone-trim",
  setup(build) {
    // Convertisseur Mermaid : ~4 Mo (mermaid, chevrotain, langium) pour une
    // boîte de dialogue que l'atelier n'ouvre jamais.
    build.onResolve({ filter: /^@excalidraw\/mermaid-to-excalidraw$/ }, () => ({
      path: "onetoone-mermaid-stub",
      namespace: "onetoone-stub",
    }));

    build.onResolve({ filter: /\/locales\/[a-zA-Z-]+-[A-Z0-9]+\.js$/ }, (args) => {
      if (KEPT_LOCALES.test(args.path)) return null;
      return { path: args.path, namespace: "onetoone-stub" };
    });

    build.onLoad({ filter: /.*/, namespace: "onetoone-stub" }, (args) => {
      if (args.path === "onetoone-mermaid-stub") {
        return {
          contents:
            "export const parseMermaidToExcalidraw = () => { throw new Error('Mermaid désactivé dans OneToOne'); };\n" +
            "export default { parseMermaidToExcalidraw };\n",
          loader: "js",
        };
      }
      // Une traduction absente : le moteur retombe sur l'anglais, clé par clé.
      return { contents: "export default {};\n", loader: "js" };
    });
  },
};

const result = await esbuild.build({
  entryPoints: ["entry.jsx"],
  bundle: true,
  minify: true,
  format: "iife",
  target: ["safari17"],
  jsx: "automatic",
  conditions: ["production"],
  loader: { ".jsx": "jsx", ".woff2": "dataurl" },
  define: {
    "process.env.NODE_ENV": '"production"',
    "process.env.PREACT": '""',
    "process.env.VITE_APP_DISABLE_TRACKING": '"true"',
  },
  plugins: [trimPlugin],
  outfile: "out/excalidraw.bundle.js",
  metafile: true,
  logLevel: "warning",
});

const outputs = result.metafile.outputs;
for (const [file, meta] of Object.entries(outputs)) {
  console.log(`   ${file} — ${(meta.bytes / 1024 / 1024).toFixed(2)} Mo`);
}
