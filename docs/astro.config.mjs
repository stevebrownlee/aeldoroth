import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://shattered-kingdoms.dev',
  srcDir: './src',
  outDir: './dist',
  integrations: [mdx(), sitemap()],
  markdown: {
    shikiConfig: {
      theme: 'dracula-soft',
    },
  },
});
