// Same-origin calls: nginx (compose) or the Ingress (Kubernetes) routes /api to the backend.
async function request(path, options = {}) {
  const res = await fetch(path, { headers: { "Content-Type": "application/json" }, ...options });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail ? JSON.stringify(body.detail) : `HTTP ${res.status}`);
  }
  return res.status === 204 ? null : res.json();
}

export const api = {
  info: () => request("/api/info"),
  stats: () => request("/api/books/stats"),
  list: (status) => request(`/api/books${status ? `?status=${status}` : ""}`),
  create: (book) => request("/api/books", { method: "POST", body: JSON.stringify(book) }),
  update: (id, patch) => request(`/api/books/${id}`, { method: "PUT", body: JSON.stringify(patch) }),
  remove: (id) => request(`/api/books/${id}`, { method: "DELETE" }),
};
