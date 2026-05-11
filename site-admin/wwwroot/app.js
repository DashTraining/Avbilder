let registrations = [];
let users = [];
let calendar = [];
let uploadRegistrationId = null;
let selectedFiles = [];

const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));

document.querySelectorAll('.tabs button').forEach(button => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.tabs button').forEach(item => item.classList.remove('active'));
    document.querySelectorAll('.view').forEach(item => item.classList.remove('active'));
    button.classList.add('active');
    document.getElementById(button.dataset.view).classList.add('active');
  });
});

document.getElementById('registrationFilter').addEventListener('input', renderRegistrations);

const dialog = document.getElementById('uploadDialog');
const dropZone = document.getElementById('dropZone');
const fileInput = document.getElementById('fileInput');

dropZone.addEventListener('dragover', event => {
  event.preventDefault();
  dropZone.classList.add('dragging');
});

dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragging'));

dropZone.addEventListener('drop', event => {
  event.preventDefault();
  dropZone.classList.remove('dragging');
  setFiles([...event.dataTransfer.files]);
});

fileInput.addEventListener('change', () => setFiles([...fileInput.files]));
document.getElementById('uploadButton').addEventListener('click', uploadPreviews);

load().catch(error => {
  document.getElementById('adminIdentity').textContent = 'Admin access failed';
  document.getElementById('registrationRows').innerHTML = `<div class="row">${escapeHtml(error.message || error)}</div>`;
});

async function load() {
  const me = await getJson('/api/me');
  document.getElementById('adminIdentity').textContent = `Signed in as ${me.email}`;

  [registrations, users, calendar] = await Promise.all([
    getJson('/api/registrations'),
    getJson('/api/users'),
    getJson('/api/calendar')
  ]);

  document.getElementById('registrationCount').textContent = registrations.length;
  document.getElementById('userCount').textContent = users.length;
  document.getElementById('readyCount').textContent = registrations.filter(item => item.previewStatus === 'Ready').length;

  renderRegistrations();
  renderUsers();
  renderCalendar();
}

async function getJson(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

function renderRegistrations() {
  const filter = document.getElementById('registrationFilter').value.toLowerCase();
  const root = document.getElementById('registrationRows');
  const items = registrations.filter(item => JSON.stringify(item).toLowerCase().includes(filter));

  if (!items.length) {
    root.innerHTML = '<div class="row">No registrations found.</div>';
    return;
  }

  root.innerHTML = items.map(item => `
    <article class="row">
      <div>
        <strong>${escapeHtml(item.sessionTitle || 'Session')}</strong>
        <span>${escapeHtml(item.preferredDate || 'No preferred date')}</span>
      </div>
      <div>
        <code>${escapeHtml(item.registrationId)}</code>
        <span>${escapeHtml(item.email)}</span>
      </div>
      <div>
        <span class="status-pill">${escapeHtml(formatRegistrationStatus(item.registrationStatus))}</span>
        <span class="status-pill ${item.previewStatus === 'Ready' ? 'ready' : ''}">${escapeHtml(formatPreviewStatus(item.previewStatus))}</span>
      </div>
      <div class="row-actions">
        <label class="date-editor">
          <span>Session date</span>
          <input type="date" value="${escapeHtml(item.preferredDate || '')}" data-date="${escapeHtml(item.registrationId)}">
        </label>
        <button data-schedule="${escapeHtml(item.registrationId)}">Approve/update date</button>
        <button class="secondary" data-upload="${escapeHtml(item.registrationId)}">Upload previews</button>
        <button class="danger" data-delete-registration="${escapeHtml(item.registrationId)}">Delete</button>
        <span class="action-status" data-action-status="${escapeHtml(item.registrationId)}" hidden></span>
      </div>
    </article>
  `).join('');

  root.querySelectorAll('[data-upload]').forEach(button => {
    button.addEventListener('click', () => openUpload(button.dataset.upload));
  });

  root.querySelectorAll('[data-schedule]').forEach(button => {
    button.addEventListener('click', () => saveSchedule(button.dataset.schedule));
  });

  root.querySelectorAll('[data-delete-registration]').forEach(button => {
    button.addEventListener('click', () => deleteRegistration(button.dataset.deleteRegistration));
  });
}

function renderUsers() {
  const root = document.getElementById('userRows');
  if (!users.length) {
    root.innerHTML = '<div class="row">No users found.</div>';
    return;
  }

  root.innerHTML = users.map(user => `
    <article class="row compact user-row">
      <div><strong>${escapeHtml(user.displayName || user.email)}</strong><span>${escapeHtml(user.email)}</span></div>
      <div><span>${escapeHtml(user.phone || 'No phone')}</span></div>
      <div><span>${escapeHtml(user.identityProvider || 'none')}</span></div>
      <div class="row-actions">
        <button class="danger" data-delete-user="${escapeHtml(user.email)}">Delete user</button>
      </div>
    </article>
  `).join('');

  root.querySelectorAll('[data-delete-user]').forEach(button => {
    button.addEventListener('click', () => deleteUser(button.dataset.deleteUser));
  });
}

function renderCalendar() {
  const root = document.getElementById('calendarRows');
  if (!calendar.length) {
    root.innerHTML = '<div class="row">No preferred dates have been submitted.</div>';
    return;
  }

  root.innerHTML = calendar.map(item => `
    <article class="row compact">
      <div><strong>${escapeHtml(item.preferredDate)}</strong><span>${escapeHtml(item.sessionTitle || 'Session')}</span></div>
      <div><code>${escapeHtml(item.registrationId)}</code></div>
      <div>
        <span>${escapeHtml(item.email)}</span>
        <div class="inline-actions">
          <input type="date" value="${escapeHtml(item.preferredDate || '')}" data-calendar-date="${escapeHtml(item.registrationId)}">
          <button data-calendar-schedule="${escapeHtml(item.registrationId)}">Approve/update</button>
          <span class="action-status" data-calendar-action-status="${escapeHtml(item.registrationId)}" hidden></span>
        </div>
      </div>
    </article>
  `).join('');

  root.querySelectorAll('[data-calendar-schedule]').forEach(button => {
    button.addEventListener('click', () => saveSchedule(button.dataset.calendarSchedule, true));
  });
}

async function saveSchedule(registrationId, fromCalendar = false) {
  const selector = fromCalendar ? `[data-calendar-date="${cssEscape(registrationId)}"]` : `[data-date="${cssEscape(registrationId)}"]`;
  const input = document.querySelector(selector);
  const buttonSelector = fromCalendar ? `[data-calendar-schedule="${cssEscape(registrationId)}"]` : `[data-schedule="${cssEscape(registrationId)}"]`;
  const button = document.querySelector(buttonSelector);
  const statusSelector = fromCalendar ? `[data-calendar-action-status="${cssEscape(registrationId)}"]` : `[data-action-status="${cssEscape(registrationId)}"]`;
  const status = document.querySelector(statusSelector);
  const preferredDate = input?.value;
  if (!preferredDate) {
    alert('Choose a session date first.');
    return;
  }

  setActionStatus(status, 'Saving...');
  if (button) button.disabled = true;

  try {
    const response = await fetch(`/api/registrations/${encodeURIComponent(registrationId)}/schedule`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ preferredDate })
    });

    if (!response.ok) {
      const message = await response.text();
      setActionStatus(status, message, true);
      alert(message);
      return;
    }

    const result = await response.json();
    const operation = result.notificationOperationId ? ` Operation: ${result.notificationOperationId}.` : '';
    const message = result.notificationStatus === 'Succeeded'
      ? `Date approved. Email accepted by ACS for ${result.customerEmail}.${operation}`
      : `Date approved. Email ${String(result.notificationStatus || 'status').toLowerCase()}: ${result.notificationMessage || 'No details returned.'}${operation}`;
    await load();
    const refreshedStatus = document.querySelector(statusSelector);
    setActionStatus(refreshedStatus, message, result.notificationStatus === 'Failed');
  } finally {
    if (button) button.disabled = false;
  }
}

function formatPreviewStatus(value) {
  if (value === 'Ready') return 'Preview status: Ready';
  if (value === 'PreviewsNotReady') return 'Preview status: Not ready';
  return 'Preview status: Not ready';
}

function formatRegistrationStatus(value) {
  if (!value) return 'Needs Approval';
  return value;
}

function setActionStatus(element, message, isError = false) {
  if (!element) return;
  element.hidden = false;
  element.textContent = message;
  element.classList.toggle('error', isError);
}

async function deleteRegistration(registrationId) {
  if (!confirm(`Delete registration ${registrationId}? Preview metadata and preview blobs for this registration will also be removed.`)) {
    return;
  }

  const response = await fetch(`/api/registrations/${encodeURIComponent(registrationId)}`, {
    method: 'DELETE'
  });

  if (!response.ok) {
    alert(await response.text());
    return;
  }

  await load();
}

async function deleteUser(email) {
  if (!confirm(`Delete user profile ${email}? Registrations are kept unless deleted separately.`)) {
    return;
  }

  const response = await fetch(`/api/users/${encodeURIComponent(email)}`, {
    method: 'DELETE'
  });

  if (!response.ok) {
    alert(await response.text());
    return;
  }

  await load();
}

function cssEscape(value) {
  if (window.CSS?.escape) return CSS.escape(value);
  return String(value).replace(/["\\]/g, '\\$&');
}

function openUpload(registrationId) {
  uploadRegistrationId = registrationId;
  selectedFiles = [];
  fileInput.value = '';
  document.getElementById('uploadContext').textContent = `Registration ${registrationId}`;
  document.getElementById('fileList').innerHTML = '';
  setUploadStatus('');
  dialog.showModal();
}

function setFiles(files) {
  selectedFiles = files.filter(file => file.type === 'image/jpeg' || /\.(jpe?g)$/i.test(file.name));
  document.getElementById('fileList').innerHTML = selectedFiles.map(file => `<span>${escapeHtml(file.name)}</span>`).join('');
}

async function uploadPreviews() {
  if (!uploadRegistrationId || !selectedFiles.length) {
    setUploadStatus('Choose one or more JPEG files.', true);
    return;
  }

  const form = new FormData();
  selectedFiles.forEach(file => form.append('files', file));
  setUploadStatus('Uploading...');

  const response = await fetch(`/api/registrations/${encodeURIComponent(uploadRegistrationId)}/previews`, {
    method: 'POST',
    body: form
  });

  if (!response.ok) {
    setUploadStatus(await response.text(), true);
    return;
  }

  const result = await response.json();
  setUploadStatus(`Published ${result.previewCount} preview images.`);
  await load();
}

function setUploadStatus(message, isError = false) {
  const el = document.getElementById('uploadStatus');
  if (!message) {
    el.hidden = true;
    el.textContent = '';
    el.className = '';
    return;
  }
  el.hidden = false;
  el.textContent = message;
  el.className = isError ? 'error' : '';
}
