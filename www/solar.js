var date = new Date(last_refresh * 1000);
document.getElementById('last_refresh').textContent = date.toLocaleString();
document.getElementById('webdata_now_p').textContent = webdata_now_p + 'W';
document.getElementById('webdata_today_e').textContent = webdata_today_e + 'kWh';
document.getElementById('webdata_total_e').textContent = webdata_total_e + 'kWh';
