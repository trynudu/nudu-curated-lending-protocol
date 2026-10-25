import { defineConfig, loadEnv } from "vite";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  return {
  root: ".",
  publicDir: "public",
  build: {
    outDir: "dist",
  },
  server: {
    port: 5173,
  },
  envPrefix: ["VITE_"],
  define: {
    "import.meta.env.VITE_BLOCKFROST_API_KEY": JSON.stringify(
      env.VITE_BLOCKFROST_API_KEY ?? env.BLOCKFROST_API_KEY ?? "",
    ),
  },
};
});
