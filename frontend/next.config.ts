import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // No `output: 'export'` here — unlike the AWS/S3+CloudFront version of this
  // app, Vercel is a native Next.js host and serves the app directly.
  images: {
    unoptimized: true
  }
};

export default nextConfig;