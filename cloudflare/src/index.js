import { Container, getContainer } from "@cloudflare/containers";
import { env as workerEnv } from "cloudflare:workers";

export class PingyBackend extends Container {
  defaultPort = Number(workerEnv.BACKEND_PORT || 4000);
  sleepAfter = "30m";

  envVars = {
    NODE_ENV: workerEnv.NODE_ENV || "production",
    PORT: workerEnv.BACKEND_PORT || "4000",
    DATABASE_URL: workerEnv.DATABASE_URL || "postgres://postgres@127.0.0.1:5432/pingy",
    ACCESS_TOKEN_SECRET:
      workerEnv.ACCESS_TOKEN_SECRET || "fallback-access-secret-please-change-this-1234567890",
    REFRESH_TOKEN_SECRET:
      workerEnv.REFRESH_TOKEN_SECRET || "fallback-refresh-secret-please-change-this-1234567890",
    ACCESS_TOKEN_TTL: workerEnv.ACCESS_TOKEN_TTL || "15m",
    REFRESH_TOKEN_DAYS: workerEnv.REFRESH_TOKEN_DAYS || "14",
    CORS_ORIGIN: workerEnv.CORS_ORIGIN || "*",
    API_RATE_LIMIT_WINDOW_MS: workerEnv.API_RATE_LIMIT_WINDOW_MS || "60000",
    API_RATE_LIMIT_MAX: workerEnv.API_RATE_LIMIT_MAX || "200",
    AUTH_RATE_LIMIT_MAX: workerEnv.AUTH_RATE_LIMIT_MAX || "40",
    MAX_FILE_SIZE_MB: workerEnv.MAX_FILE_SIZE_MB || "25",
    S3_REGION: workerEnv.S3_REGION || "",
    S3_ENDPOINT: workerEnv.S3_ENDPOINT || "",
    S3_BUCKET: workerEnv.S3_BUCKET || "",
    S3_ACCESS_KEY_ID: workerEnv.S3_ACCESS_KEY_ID || "",
    S3_SECRET_ACCESS_KEY: workerEnv.S3_SECRET_ACCESS_KEY || "",
    S3_PUBLIC_BASE_URL: workerEnv.S3_PUBLIC_BASE_URL || "",
  };
}

const shouldRouteToBackend = (pathname) => {
  return (
    pathname.startsWith("/api") ||
    pathname.startsWith("/socket.io") ||
    pathname.startsWith("/uploads")
  );
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (shouldRouteToBackend(url.pathname)) {
      const backend = getContainer(env.PINGY_BACKEND);
      return backend.fetch(request);
    }

    const assetResponse = await env.ASSETS.fetch(request);

    if (assetResponse.status !== 404) {
      return assetResponse;
    }

    return env.ASSETS.fetch(new Request(new URL("/", request.url), request));
  },
};
