import { defineCollection, z } from 'astro:content';

const docs = defineCollection({
  schema: z.object({
    title: z.string(),
    description: z.string(),
    order: z.number(),
    category: z.enum([
      'Foundation',
      'Architecture',
      'Agents & Referee',
      'Protocol & Tooling',
      'Ecosystem',
    ]),
    tags: z.array(z.string()).default([]),
    updatedAt: z.string().optional(),
  }),
});

export const collections = { docs };
