let last_refresh = 0;
const imgs = document.querySelectorAll('img');

async function fetchJSON() {
    try {
      const response = await fetch('data/data.json');
      const data = await response.json();
      parseData(data);
    }
    catch (err) {
      console.log(err);
    }
}

function parseData(data) {
    if (last_refresh === data.last_refresh) {
        // data not changed
        return;
    }
    last_refresh = data.last_refresh;
    var date = new Date(data.last_refresh * 1000);
    document.getElementById('last_refresh').textContent = date.toLocaleString();
    document.getElementById('webdata_now_p').textContent = data.webdata_now_p + 'W';
    document.getElementById('webdata_today_e').textContent = data.webdata_today_e + 'kWh';
    document.getElementById('webdata_total_e').textContent = data.webdata_total_e + 'kWh';
    document.title = 'Solar: ' + data.webdata_now_p + 'W';
    for (const img of imgs) {
        img.src = img.getAttribute('data-src') + '?' + last_refresh;
    }
}

// initial fetch
fetchJSON();

// refresh each minute
setInterval(function() {
    fetchJSON();
}, 60000);
