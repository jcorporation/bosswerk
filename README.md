This is my small framework to fetch, store and display data from my Bosswerk inverter.

- Fetches current power from a Bosswerk inverter
- Saves the current power in a rrd file
- Displays current and historical data via html

## Dependencies

- bash
- curl
- rrdtool

## Usage

Do not run this script as root, create a separate user for it.

```
useradd -m solar
sudo -i -u solar
```

### Clone the repo

```
git clone https://github.com/jcorporation/bosswerk.git
```

### Add the http uri to fetch data from

```
cd bosswerk
echo "PV_URI=\"http://10.10.100.254/status.html\"" > .config
```

### Add a .netrc file for authentication (user home)

```
cat > ~/.netrc << EOL
machine 10.10.100.254
login admin
password admin

EOL
```

### Add a crontab entry

Run the script only at daytime every 5 minutes. The rrdfile expects one datapoint each 5 minutes.

```
*/5 6-20 * * *	/home/solar/bosswerk/solar.sh 2>&1 | logger -p local1.info
```

### Publish

Publish the `www` directory via nginx:

```
location /bosswerk {
  alias /home/solar/bosswerk/www;
}

```
