async     = require 'async'
cheerio   = require 'cheerio'
csv       = require 'csv-write-stream'
debug     = require('debug') 'motorbike'
fs        = require 'fs'
path      = require 'path'
request   = require 'superagent'

stringToKey = (input) ->
  input.toLowerCase()
  .replace(/[^a-z]+/g, ' ')
  .trim()
  .replace(/\s+/g, '-')

bot =
  root: 'http://bikez.com'
  stream: null

bot.before = ->
  bot.stream = csv()
  src = path.join __dirname, '../data/database.csv'
  bot.stream.pipe fs.createWriteStream(src)

bot.after = ->
  bot.stream.end()

bot.fetchBrands = (callback) ->
  debug 'fetch brands'
  request.get "#{bot.root}/brands/index.php"
  .end (err, res) ->
    return callback err if err
    if res.status isnt 200
      return callback new Error res.text
    debug 'analyse page'
    $ = cheerio.load res.text
    list = $('table.zebra')
    .find('tr')
    .filter ->
      return @name is 'tr' and
        @attribs?.class in ['odd', 'even']
    .map ->
      link = $(@).find('td a')
      name = link.text()
      match = name.match /^(.*)\s+motorcycles$/
      if match
        name = match[1]
      name: name
      link: bot.root + link.attr('href')
    .get()
    async.eachSeries list, bot.fetchBrand, callback

bot.fetchBrand = (brand, callback) ->
  debug "fetch brand #{brand.name}"
  request.get brand.link
  .end (err, res) ->
    return callback err if err
    if res.status isnt 200
      return callback new Error res.text
    debug 'analyse page'
    $ = cheerio.load res.text
    list = $('table.zebra')
    .find('tr a')
    .filter ->
      current = $(@)
      return current.attr('href')?.match(/^\.\.\/motorcycles/) and
        current.text().length > 0
    .map ->
      name = $(@).text()
      name = name.substring(brand.name.length + 1)
      name: name
      link: bot.root + $(@).attr('href').substring 2
    .get()
    async.eachSeries list, (model, done) ->
      bot.fetchModel brand, model, done
    , callback

bot.fetchModel = (brand, model, callback) ->
  debug "fetch model #{brand.name} #{model.name}"
  request.get model.link
  .end (err, res) ->
    return callback err if err
    if res.status isnt 200
      return callback new Error res.text
    $ = cheerio.load res.text
    list = $('table.Grid')
    .find('tr')
    .filter ->
      return $(@).find('td').length is 2
    .map ->
      key: stringToKey $(@).find('td:first-of-type').text()
      value: $(@).find('td:last-of-type').text()
    .get()
    informations =
      brand: brand.name
      model: model.name
    for item in list
      informations[item.key] = item.value
    bot.stream.write informations
    callback()

bot.run = (callback) ->
  debug 'start process'
  bot.before()
  bot.fetchBrands (err) ->
    bot.after()
    callback err

bot.run (err) ->
  if err
    debug err
    process.exit 1
  process.exit 0
