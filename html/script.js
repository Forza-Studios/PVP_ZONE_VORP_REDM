$(document).ready(function () {
    window.addEventListener('message', function (event) {
        var item = event.data;

        if (item.action === "show") {
            $("#container").fadeIn(500);
        } else if (item.action === "hide") {
            $("#container").fadeOut(500);
        } else if (item.action === "update") {
            var topList = item.top;

            for (let i = 0; i < 3; i++) {
                let rank = i + 1;
                if (topList[i]) {
                    $("#name-" + rank).text(topList[i].name);
                    $("#kills-" + rank).text(topList[i].kills);
                } else {
                    $("#name-" + rank).text("---");
                    $("#kills-" + rank).text("0");
                }
            }
        } else if (item.action === "updateSelf") {
            $("#my-name").text(item.name);
            $("#my-kills").text(item.kills);
        } else if (item.action === "notify") {
            $("#notify-message").text(item.message);
            $("#notify-container").fadeIn(500);

            setTimeout(function () {
                $("#notify-container").fadeOut(500);
            }, 4000);
        } else if (item.action === "killFeed") {
            var streakClass = "";
            var separator = '<span class="sword-icon">&#9876;</span>'; // HTML Entity for Swords
            var streak = item.streak || 0;

            if (streak >= 10) {
                streakClass = "streak-10";
                separator = '<span class="lightning-icon">&#9889;</span>'; // HTML Entity for Lightning ⚡
            } else if (streak >= 5) {
                streakClass = "streak-5";
            }

            // Safe string concatenation instead of backticks to avoid iterator issues in some engines
            var feedItem = '<div class="feed-item ' + streakClass + '">' +
                '<span class="killer-name">' + item.killer + '</span>' +
                separator +
                '<span class="victim-name">' + item.victim + '</span>' +
                '</div>';

            var $item = $(feedItem).appendTo("#kill-feed-container");

            setTimeout(function () {
                $item.fadeOut(500, function () { $(this).remove(); });
            }, 5000);
        }
    });
});
