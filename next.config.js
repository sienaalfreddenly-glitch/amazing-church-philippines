/** @type {import('next').NextConfig} */
const nextConfig = {
  // Emits .next/standalone with a minimal server and only the node_modules it
  // actually uses, which is what the Docker image runs.
  output: 'standalone',
  images: { remotePatterns: [{ protocol: 'https', hostname: '**' }] },
};
module.exports = nextConfig;
