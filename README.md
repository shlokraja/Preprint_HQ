# Foodbox-HQ
This is the repo for the HQ side of food box.

## Prerequisites before working with the app
1. Install node and npm in your machine
```
sudo apt-get install build-essential
curl -sL https://deb.nodesource.com/setup | sudo bash -
sudo apt-get install nodejs
```
(This will install both node and npm)

2. Install docker
```
sudo sh -c "echo deb https://get.docker.com/ubuntu docker main > /etc/apt/sources.list.d/docker.list"
curl -s https://get.docker.com/gpg | sudoapt-key add -
sudo apt-get update
sudo apt-get install lxc-docker
```

## Steps to start the app
1. npm install
2. Have a .bootstraprc file in the home dir of your repo
Eg -
```
export DEBUG=Foodbox-HQ:server
export PORT=8080
export NODE_ENV=development

#DB credentials stuff
export DB_CONN=postgres://username:password@localhost/testdb
```
3. Source the file.
```
. .bootstraprc
```
4. Execute the steps given in scripts/schema.sql
5. Start the app
```
npm start
```

Or alternatively, you can use nodemon for live reload.
```
npm run nodemon
```

## Steps to test the app
1. Run steps 1-4 in the first section
2. Ensure you have the postgres DB up and running with atleast one row in each table
3. npm test

## Steps to check for lint errors
1. Run steps 1-3 in the first section
2. npm run lint

