import { api } from "./api.js";
import "./style.css";

const LABELS = { want_to_read: "Want to read", reading: "Reading", finished: "Finished" };
let filter = "";

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

function statusSelect(book) {
  const opts = Object.entries(LABELS)
    .map(([v, l]) => `<option value="${v}" ${v === book.status ? "selected" : ""}>${l}</option>`)
    .join("");
  return `<select class="status ${book.status}" data-id="${book.id}">${opts}</select>`;
}

async function refresh() {
  try {
    const [stats, books] = await Promise.all([api.stats(), api.list(filter)]);
    $("k-total").textContent = stats.total;
    $("k-reading").textContent = stats.by_status.reading;
    $("k-finished").textContent = stats.by_status.finished;
    $("k-pages").textContent = stats.pages_read.toLocaleString();
    $("k-rating").textContent = stats.average_rating ?? "-";
    $("books").innerHTML = books.length
      ? books.map((b) => `<tr>
          <td data-label="Title"><strong>${esc(b.title)}</strong></td>
          <td data-label="Author">${esc(b.author)}</td>
          <td data-label="Status">${statusSelect(b)}</td>
          <td data-label="Pages">${b.pages}</td>
          <td data-label="Rating">${b.rating ? "&#9733;".repeat(b.rating) : "-"}</td>
          <td><button class="danger" data-del="${b.id}" title="Delete">Delete</button></td>
        </tr>`).join("")
      : `<tr><td colspan="6" class="muted">No books here yet - add one on the left.</td></tr>`;
  } catch (err) {
    $("books").innerHTML = `<tr><td colspan="6" class="error">Backend unreachable: ${esc(err.message)}</td></tr>`;
  }
}

$("add-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const f = new FormData(e.target);
  const book = {
    title: f.get("title"), author: f.get("author"), status: f.get("status"),
    pages: Number(f.get("pages") || 0), rating: f.get("rating") ? Number(f.get("rating")) : null,
  };
  try {
    const created = await api.create(book);
    $("form-msg").textContent = `Added "${created.title}" (id ${created.id})`;
    e.target.reset();
    refresh();
  } catch (err) {
    $("form-msg").textContent = `Error: ${err.message}`;
  }
});

$("filters").addEventListener("click", (e) => {
  if (e.target.tagName !== "BUTTON") return;
  filter = e.target.dataset.status;
  document.querySelectorAll("#filters button").forEach((b) => b.classList.toggle("active", b === e.target));
  refresh();
});

$("books").addEventListener("change", async (e) => {
  if (e.target.matches("select.status")) {
    await api.update(e.target.dataset.id, { status: e.target.value });
    refresh();
  }
});

$("books").addEventListener("click", async (e) => {
  if (e.target.dataset.del) {
    await api.remove(e.target.dataset.del);
    refresh();
  }
});

api.info().then((i) => {
  $("welcome").textContent = i.message;
  $("env").textContent = `env: ${i.env} | api ${i.version.slice(0, 12)}`;
}).catch(() => { $("welcome").textContent = "Backend not reachable"; });

refresh();
