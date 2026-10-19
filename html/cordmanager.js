/* ========================================
   PvP Zone Cord Manager - Frontend Logic
   ======================================== */

const RESOURCE = 'coi-pvpzone';

let cords = [];

// Open Cord Manager
function openCordManager() {
    $('#cordManager').fadeIn(300);
    requestCords();
}

// Close Cord Manager
function closeCordManager() {
    $('#cordManager').fadeOut(200);
    cords = [];
    renderCords();
}

// Request cords from server via NUI callback
function requestCords() {
    fetch(`http://${RESOURCE}/cordManagerGetCords`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).catch(err => console.error('[CordManager] getCords error:', err));
}

// Add a new zone cord
function addCord(data) {
    fetch(`http://${RESOURCE}/cordManagerAdd`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    }).then(res => res.ok ? requestCords() : Promise.reject(res))
      .catch(err => console.error('[CordManager] addCord error:', err));
}

// Remove a zone cord by ID
function removeCord(id) {
    if (!confirm('Remove this zone cord from the database?')) return;
    fetch(`http://${RESOURCE}/cordManagerRemove`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: id })
    }).then(res => res.ok ? requestCords() : Promise.reject(res))
      .catch(err => console.error('[CordManager] removeCord error:', err));
}

// Render cords list
function renderCords() {
    const $list = $('#cordsList');
    $list.empty();

    if (!cords || cords.length === 0) {
        $list.append('<div class="cm-cord-item empty">No zone cords in database</div>');
        return;
    }

    cords.forEach(cord => {
        const $item = $(`
            <div class="cm-cord-item">
                <div class="cm-cord-header">
                    <span class="cm-cord-name">${escapeHtml(cord.name)}</span>
                </div>
                <div class="cm-cord-coords">
                    X: ${cord.x} &nbsp;|&nbsp; Y: ${cord.y} &nbsp;|&nbsp; Z: ${cord.z} &nbsp;|&nbsp; Radius: ${cord.radius || 200.0}
                </div>
                <div class="cm-cord-actions">
                    <button class="cm-btn-remove" data-id="${cord.id}">Remove</button>
                </div>
            </div>
        `);
        $item.find('.cm-btn-remove').on('click', function() {
            removeCord($(this).data('id'));
        });
        $list.append($item);
    });
}

// Escape HTML to prevent injection
function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Listen for NUI messages
window.addEventListener('message', function(event) {
    const item = event.data;

    if (item.action === 'openCordManager') {
        openCordManager();
    } else if (item.action === 'closeCordManager') {
        closeCordManager();
    } else if (item.action === 'updateCords') {
        cords = item.cords || [];
        renderCords();
    }
});

// DOM Ready
$(document).ready(function() {
    // Close button
    $('#closeCordManager').on('click', function() {
        closeCordManager();
        // Notify client to release NUI focus
        fetch(`http://${RESOURCE}/cordManagerClose`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    });

    // Add cord form
    $('#addCordForm').on('submit', function(e) {
        e.preventDefault();
        const data = {
            name: $('#cordName').val().trim(),
            x: $('#cordX').val(),
            y: $('#cordY').val(),
            z: $('#cordZ').val(),
            radius: $('#cordRadius').val() || 200.0
        };

        if (!data.name) {
            alert('Please enter a zone name.');
            return;
        }

        // Reset form
        $('#addCordForm')[0].reset();
        $('#cordRadius').val('200.0');

        addCord(data);
    });
});
