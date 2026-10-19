/* ============================================================
   PvP Zone Leaderboard & Cord Manager (Vanilla JS)
   ============================================================ */

document.addEventListener('DOMContentLoaded', () => {
    const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'coi-pvpzone';

    // Helper: NUI Callback Post
    function postNUI(callbackName, data = {}) {
        return fetch(`https://${resourceName}/${callbackName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data)
        }).catch(err => {
            console.error(`[PvPZone NUI] Error in ${callbackName}:`, err);
        });
    }

    // Helper: Safe HTML Escaping
    function escapeHtml(str) {
        if (!str) return '';
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    // DOM Elements - Leaderboard
    const hudContainer = document.getElementById('container');
    const myNameEl = document.getElementById('my-name');
    const myKillsEl = document.getElementById('my-kills');

    // DOM Elements - Notification
    const notifyContainer = document.getElementById('notify-container');
    const notifyMsgEl = document.getElementById('notify-message');
    let notifyTimeout = null;

    // DOM Elements - Kill Feed
    const killFeedContainer = document.getElementById('kill-feed-container');

    // DOM Elements - Cord Manager
    const cmOverlay = document.getElementById('cordManagerOverlay');
    const closeCmBtn = document.getElementById('closeCordManager');
    const addCordForm = document.getElementById('addCordForm');
    const cordsListEl = document.getElementById('cordsList');
    const zoneCountBadge = document.getElementById('zoneCountBadge');
    const btnFillCoords = document.getElementById('btnFillCoords');

    let currentCords = [];

    // ============================================================
    // Leaderboard Controls
    // ============================================================
    function showHUD() {
        hudContainer.style.display = 'flex';
        // Trigger reflow for CSS transition
        void hudContainer.offsetWidth;
        hudContainer.classList.add('visible');
    }

    function hideHUD() {
        hudContainer.classList.remove('visible');
        setTimeout(() => {
            if (!hudContainer.classList.contains('visible')) {
                hudContainer.style.display = 'none';
            }
        }, 350);
    }

    function updateLeaderboard(topList = []) {
        for (let i = 0; i < 3; i++) {
            const rank = i + 1;
            const nameEl = document.getElementById(`name-${rank}`);
            const killsEl = document.getElementById(`kills-${rank}`);

            if (topList[i]) {
                if (nameEl) nameEl.textContent = topList[i].name || '---';
                if (killsEl) killsEl.textContent = topList[i].kills ?? 0;
            } else {
                if (nameEl) nameEl.textContent = '---';
                if (killsEl) killsEl.textContent = '0';
            }
        }
    }

    function updateSelf(data = {}) {
        if (myNameEl) myNameEl.textContent = data.name || 'YOU';
        if (myKillsEl) myKillsEl.textContent = data.kills ?? 0;
    }

    // ============================================================
    // Notification Toast
    // ============================================================
    function showNotification(message) {
        if (!notifyContainer || !notifyMsgEl) return;

        if (notifyTimeout) {
            clearTimeout(notifyTimeout);
            notifyTimeout = null;
        }

        notifyMsgEl.textContent = message;
        notifyContainer.style.display = 'flex';
        void notifyContainer.offsetWidth;
        notifyContainer.classList.add('visible');

        notifyTimeout = setTimeout(() => {
            notifyContainer.classList.remove('visible');
            setTimeout(() => {
                if (!notifyContainer.classList.contains('visible')) {
                    notifyContainer.style.display = 'none';
                }
            }, 350);
        }, 3500);
    }

    // ============================================================
    // Kill Feed
    // ============================================================
    function addKillFeed(killer, victim, streak = 0) {
        if (!killFeedContainer) return;

        const feedItem = document.createElement('div');
        feedItem.className = 'feed-item';

        let separator = '<span class="sword-icon">⚔️</span>';
        let badgeHtml = '';

        if (streak >= 10) {
            feedItem.classList.add('streak-10');
            separator = '<span class="lightning-icon">⚡</span>';
            badgeHtml = `<span class="streak-badge">${streak} STREAK</span>`;
        } else if (streak >= 5) {
            feedItem.classList.add('streak-5');
            separator = '<span class="sword-icon">👑</span>';
            badgeHtml = `<span class="streak-badge">${streak} STREAK</span>`;
        }

        feedItem.innerHTML = `
            <span class="killer-name">${escapeHtml(killer)}</span>
            ${badgeHtml}
            ${separator}
            <span class="victim-name">${escapeHtml(victim)}</span>
        `;

        killFeedContainer.appendChild(feedItem);

        // Animate in
        requestAnimationFrame(() => {
            feedItem.classList.add('show');
        });

        // Auto remove after 5s
        setTimeout(() => {
            feedItem.classList.remove('show');
            setTimeout(() => {
                if (feedItem.parentNode) feedItem.remove();
            }, 300);
        }, 5000);
    }

    // ============================================================
    // Cord Manager (Admin)
    // ============================================================
    function openCordManager() {
        if (!cmOverlay) return;
        cmOverlay.style.display = 'flex';
        void cmOverlay.offsetWidth;
        cmOverlay.classList.add('open');
        postNUI('cordManagerGetCords');
    }

    function closeCordManager() {
        if (!cmOverlay) return;
        cmOverlay.classList.remove('open');
        setTimeout(() => {
            if (!cmOverlay.classList.contains('open')) {
                cmOverlay.style.display = 'none';
            }
        }, 250);
        postNUI('cordManagerClose');
    }

    function renderCordsList(cords = []) {
        currentCords = cords;
        if (!cordsListEl) return;
        cordsListEl.innerHTML = '';

        if (zoneCountBadge) {
            zoneCountBadge.textContent = `${cords.length} Zone${cords.length === 1 ? '' : 's'}`;
        }

        if (!cords || cords.length === 0) {
            cordsListEl.innerHTML = '<div class="cm-cord-item empty">No zones configured yet in database</div>';
            return;
        }

        cords.forEach(zone => {
            const item = document.createElement('div');
            item.className = 'cm-cord-item';

            const name = escapeHtml(zone.name || 'Unnamed Zone');
            const x = Number(zone.x || 0).toFixed(2);
            const y = Number(zone.y || 0).toFixed(2);
            const z = Number(zone.z || 0).toFixed(2);
            const r = Number(zone.radius || 200).toFixed(0);

            item.innerHTML = `
                <div class="cm-cord-details">
                    <span class="cm-cord-name">${name}</span>
                    <span class="cm-cord-coords">X: ${x} | Y: ${y} | Z: ${z} | Radius: ${r}m</span>
                </div>
                <button type="button" class="cm-btn-remove" data-id="${zone.id}">Delete</button>
            `;

            const removeBtn = item.querySelector('.cm-btn-remove');
            removeBtn.addEventListener('click', () => {
                postNUI('cordManagerRemove', { id: zone.id });
            });

            cordsListEl.appendChild(item);
        });
    }

    // Fill current coords
    if (btnFillCoords) {
        btnFillCoords.addEventListener('click', () => {
            fetch(`https://${resourceName}/cordManagerGetCurrentCoords`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({})
            })
            .then(res => res.json())
            .then(data => {
                if (data && data.x !== undefined) {
                    document.getElementById('cordX').value = data.x;
                    document.getElementById('cordY').value = data.y;
                    document.getElementById('cordZ').value = data.z;
                }
            })
            .catch(err => console.error('[PvPZone NUI] Get current coords error:', err));
        });
    }

    // Add Form Submit
    if (addCordForm) {
        addCordForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const nameInput = document.getElementById('cordName');
            const xInput = document.getElementById('cordX');
            const yInput = document.getElementById('cordY');
            const zInput = document.getElementById('cordZ');
            const radiusInput = document.getElementById('cordRadius');

            const payload = {
                name: nameInput.value.trim(),
                x: parseFloat(xInput.value),
                y: parseFloat(yInput.value),
                z: parseFloat(zInput.value),
                radius: parseFloat(radiusInput.value) || 200.0
            };

            if (!payload.name) return;

            postNUI('cordManagerAdd', payload);

            nameInput.value = '';
            xInput.value = '';
            yInput.value = '';
            zInput.value = '';
            radiusInput.value = '200.0';
        });
    }

    // Close button
    if (closeCmBtn) {
        closeCmBtn.addEventListener('click', closeCordManager);
    }

    // ESC Key to Close
    window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (cmOverlay && cmOverlay.classList.contains('open')) {
                closeCordManager();
            }
        }
    });

    // ============================================================
    // Incoming NUI Messages
    // ============================================================
    window.addEventListener('message', (event) => {
        const item = event.data;
        if (!item || !item.action) return;

        switch (item.action) {
            case 'show':
                showHUD();
                break;
            case 'hide':
                hideHUD();
                break;
            case 'update':
                updateLeaderboard(item.top || []);
                break;
            case 'updateSelf':
                updateSelf({ name: item.name, kills: item.kills });
                break;
            case 'notify':
                showNotification(item.message || '');
                break;
            case 'killFeed':
                addKillFeed(item.killer, item.victim, item.streak || 0);
                break;
            case 'openCordManager':
                openCordManager();
                break;
            case 'closeCordManager':
                closeCordManager();
                break;
            case 'updateCords':
                renderCordsList(item.cords || []);
                break;
            default:
                break;
        }
    });
});
