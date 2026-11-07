const TEMPLATE_SRC =
  "https://github.com/jesuisban22-code/nex-template/releases/download/template-v1/template.exe";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
          "Access-Control-Allow-Headers": "*",
        },
      });
    }

    if (path === "/api/template" || path === "/template.exe") {
      try {
        const upstream = await fetch(TEMPLATE_SRC, {
          redirect: "follow",
          headers: { "User-Agent": "Mozilla/5.0 NexShop-Template-Proxy/1" },
        });
        if (!upstream.ok) {
          return new Response(
            "upstream " + upstream.status + " for " + TEMPLATE_SRC,
            { status: 502, headers: { "Content-Type": "text/plain" } }
          );
        }
        return new Response(upstream.body, {
          status: 200,
          headers: {
            "Content-Type": "application/octet-stream",
            "Content-Disposition": 'attachment; filename="template.exe"',
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=120",
          },
        });
      } catch (e) {
        return new Response("proxy error: " + String(e), {
          status: 500,
          headers: { "Content-Type": "text/plain" },
        });
      }
    }

    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }
    return new Response("no assets binding", { status: 500 });
  },
};
