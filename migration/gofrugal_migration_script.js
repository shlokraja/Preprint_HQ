#!/usr/bin/env node

var _ = require('underscore');
var moment = require('moment');
var async = require('async');
var dbUtils = require('../models/dbUtils');
var fs = require('fs');
var csv = require('fast-csv');
var assert = require('assert');
 
var program = require('commander');
 
program
  .version('0.0.1')
  .option('-r, --restaurant-id <n>', 'Restaurant Id from database', Number)
  .option('-o, --outlet-id <n>', 'Outlet id from database', Number)
  .option('-p, --purchase-order-csv <path>', 'Purchase order details csv file')
  .option('-s, --sales-details-csv <path>', 'Sales details csv file')
  .option('-h, --hourly-sales-csv <path>', 'Hourly sales csv file')
  .option('-w, --wastage-csv <path>', 'Wastage details csv file')
  .parse(process.argv);
 
console.log('Migrating data :');
console.log('restaurant id : %j', program.restaurantId);
console.log('outlet id : %j', program.outletId);
console.log('puchase details csv file : %s', program.purchaseOrderCsv);
console.log('sales details csv file : %s', program.salesDetailsCsv);
console.log('hourly sales csv file : %s', program.hourlySalesCsv);
console.log('wastage details csv file : %s', program.wastageCsv);

// Details
var restaurantId = program.restaurantId;
var outletId = program.outletId;
var poCsvPath = program.purchaseOrderCsv;
var salesCsvPath = program.salesDetailsCsv;
var hourlyCsvPath = program.hourlySalesCsv;
var wastageCsvPath = program.wastageCsv;

var purchase_details = [];
var sales_details = [];
var wastage_details = [];

// Handles each row in csv data sheet
var poDetailsHandler = function(data) {
  var r = {};
  r["sales_date"] = moment(data[1].trim(), "DD/MM/YYYY").format('YYYY-MM-DD');
  r["mr_code"] = data[20];
  r["status"] = "sold";
  r["selling_price"] = Number(data[7]);
  r["mrp"] = Number(data[8]);
  r["restaurant_fee"] = Number(data[6]);
  r["foodbox_fee"] = Number(data[35]);
  r["qty"] = Number(data[5]);
  r["barcode"] = data[33];
  r["item_id"] = Number(data[3]);
  r["item_name"] = data[4].trim();
  //console.log(r);
  purchase_details.push(r);
};

var salesDetailsHandler = function(data) {
  var r = {};
  r["sales_date"] = moment(data[6].trim(), "DD/MM/YYYY").format('YYYY-MM-DD');
  r["qty"] = Number(data[1]);
  r["gross_sales"] = Number(data[3]);
  r["vat"] = Number(data[4]);
  r["st"] = Number(data[7]);
  r["item_id"] = Number(data[9]);
  r["time_of_day"] = data[13];
  //console.log(r);
  sales_details.push(r);  
};

var wastageDataHandler = function(data) {
  var r = {};
  r["sales_date"] = moment(data[1].trim(), "DD/MM/YYYY").format('YYYY-MM-DD');
  r["item_id"] = Number(data[2]);
  r["qty"] = Number(data[4]);
  r["status"] = data[7];
  r["time_of_day"] = data[19];
  r["foodbox_fee"] = Number(data[8]);
  r["mrp"] = Number(data[9]);
  r["selling_price"] = Number(data[12]);
  //console.log(r);
  wastage_details.push(r);
};

// Read data from csv files
async.series([
    function(callback){
      readCsv(poCsvPath, poDetailsHandler, callback);
    },
    function(callback){
      readCsv(salesCsvPath, salesDetailsHandler, callback);
    },
    function(callback){
      readCsv(wastageCsvPath, wastageDataHandler, callback);
    }
  ],
  function(err, results){
    if(err) {
      console.error(err);
    }
    // upload to db
    uploadSalesToDb();
});

function readCsv(path, handler, callback) {
  csv.fromPath(path)
    .on("data", handler)
    .on("end", function(){
      console.log("done");
      callback(null, 1);
  });
}

// DB upload and verification.
function uploadSalesToDb() {
  // verify data consistency across csvs.
  var salesByDays = _.groupBy(sales_details, "sales_date");
  _.each(_.keys(salesByDays), function(sales_date){
    var salesOnDate = salesByDays[sales_date];
    var salesByItems = _.groupBy(salesOnDate, "item_id");
    _.each(_.keys(salesByItems), function(item_id){
      var salesOnItem = salesByItems[item_id];
      // match
      //console.log(salesOnItem);
      matchPurchasesWithSales(sales_date, item_id);
    });
  });
}

function uploadWastageToDb() {

}

function matchPurchasesWithSales(date, itemId) {
  console.log("Verifying Item: " + itemId + ", date: " + date);
  var salesData =  matchesWith(sales_details, date, itemId);
  var poData = matchesWith(purchase_details, date, itemId);
  var wastageData = matchesWith(wastage_details, date, itemId);

  console.log(salesData);
  console.log(poData);
  console.log(wastageData);

  // match total quantity
  var purchaseQty = aggregateByColumn(poData, 'qty');
  console.log("purchases: " + purchaseQty);

  var salesQty = aggregateByColumn(salesData, 'qty');
  console.log("sales: " + salesQty);

  var wastageQty = aggregateByColumn(wastageData, 'qty');

  assert.equal(purchaseQty, salesQty + wastageQty);
}

function matchesWith(items, date, itemId){
  return  _.filter(items, function(it){
    return it.item_id == itemId && it.sales_date == date;
  });
}

function aggregateByColumn(items, name) {
  return _.reduce(items, function(memo, item){
    return memo + item[name];
  }, 0);
}
