/*global console require module*/
'use strict';

var express = require('express');
var router = express.Router();
var pdf = require('html-pdf');
var cheerio = require('cheerio');
var randomstring = require('randomstring');
var debug = require('debug')('Foodbox-HQ:server');
var format = require('string-format');
var path = require('path')

format.extend(String.prototype);
var config = require('../models/config');
var conString = config.dbConn;

// Handlers for bill related code

// This returns the bill pdf given the file name
router.get('/:id', function(req, res, next) {
  // XXX: Its better to group the files according to day/month than to
  // keep them in a single folder
  var bill_file_code = req.params.id;
  var filePath = process.env.BILL_FOLDER;
  filePath = path.join(filePath, 'bill-' + bill_file_code + '.pdf');
  res.sendFile(filePath);
});

// This creates a pdf file from the given html and stores it.
router.post('/', function(req, res, next) {
  // getting the bill html
  var bill_text = req.body.bill_text;
  // parsing it into cheerio struct
  var $ = cheerio.load(bill_text);
  // Filling the images in the html
  var filePath = path.join(__dirname, '/../');
  filePath = path.join(filePath, 'public/img/email.png');
  $("#mail img").attr("src", 'file://' + filePath);

  filePath = path.join(__dirname, '/../');
  filePath = path.join(filePath, 'public/img/fb.png');
  $("#fb img").attr("src", 'file://' + filePath);

  filePath = path.join(__dirname, '/../');
  filePath = path.join(filePath, 'public/img/twitter.png');
  $("#twitter img").attr("src", 'file://' + filePath);

  var rand_string = randomstring.generate(5);
  var bill_file = 'bill-' + rand_string + '.pdf';
  var bill_folder = process.env.BILL_FOLDER;
  var options = { filename: path.join(bill_folder, bill_file), format: 'Letter' };
  debug('Bill location- ' + options.filename);
  // converting the pdf file to a buffer and passing it along to the print function
  pdf.create($.html(), options).toFile(function(err, buffer) {
    if (err) return console.error(err);
    debug('Bill {} successfully generated'.format(options.filename));
    res.send({"bill_location": "/bill/"+rand_string});
  });
});

module.exports = router;
