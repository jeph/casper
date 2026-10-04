import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";

// Vercel sets this to the production domain during its builds. Local builds are served by `astro dev` and
// `astro preview` on Astro's default port.
const vercelHost = process.env.VERCEL_PROJECT_PRODUCTION_URL;

export default defineConfig({
  site: vercelHost ? `https://${vercelHost}` : "http://localhost:4321",
  integrations: [
    starlight({
      title: "Casper",
      description: "Private, on-device dictation for the Mac.",
      logo: { src: "./src/assets/ghost.svg" },
      favicon: "/favicon.svg",
      social: [{ icon: "github", label: "GitHub", href: "https://github.com/jeph/casper" }],
      customCss: ["./src/styles/docs.css"],
      sidebar: [{ autogenerate: { directory: "docs" } }],
      disable404Route: true,
    }),
  ],
});
