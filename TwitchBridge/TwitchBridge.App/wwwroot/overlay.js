// Connects to OverlayHttpServer's /ws endpoint and renders toasts + the
// live poll widget. Reconnects automatically if TwitchBridge restarts.

const toastStack = document.getElementById("toast-stack");
const pollWidget = document.getElementById("poll-widget");
const pollCandidates = document.getElementById("poll-candidates");
const pollTimer = document.getElementById("poll-timer");

function connect() {
  const ws = new WebSocket(`ws://${location.host}/ws`);

  ws.onmessage = (event) => {
    try {
      const payload = JSON.parse(event.data);
      handleMessage(payload);
    } catch (err) {
      console.error("Bad overlay message", err, event.data);
    }
  };

  ws.onclose = () => setTimeout(connect, 2000);
  ws.onerror = () => ws.close();
}

function handleMessage(payload) {
  switch (payload.type) {
    case "toast":
    case "command_result":
    case "engine_event":
      showToast(payload.text ?? payload.message ?? "");
      break;
    case "poll_update":
      renderPoll(payload);
      break;
    default:
      break;
  }
}

function showToast(text) {
  if (!text) return;
  const el = document.createElement("div");
  el.className = "toast";
  el.textContent = text;
  toastStack.appendChild(el);
  setTimeout(() => el.remove(), 6000);
}

function renderPoll(payload) {
  if (!payload.active) {
    pollWidget.classList.add("hidden");
    return;
  }

  pollWidget.classList.remove("hidden");
  pollCandidates.innerHTML = "";

  const totalVotes = (payload.candidates ?? []).reduce((sum, c) => sum + c.votes, 0) || 1;
  for (const candidate of payload.candidates ?? []) {
    const row = document.createElement("div");
    const pct = Math.round((candidate.votes / totalVotes) * 100);

    const bar = document.createElement("div");
    bar.className = "poll-candidate-bar";
    bar.style.width = `${pct}%`;

    const label = document.createElement("div");
    label.className = "poll-candidate";
    label.innerHTML = `<span>!vote ${candidate.ballot} — ${candidate.displayName}</span><span>${candidate.votes}</span>`;

    row.appendChild(bar);
    row.appendChild(label);
    pollCandidates.appendChild(row);
  }

  pollTimer.textContent = payload.secondsRemaining != null ? `${payload.secondsRemaining}s left` : "";
}

connect();
