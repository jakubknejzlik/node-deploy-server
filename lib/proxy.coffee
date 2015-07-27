http = require('http')
httpProxy = require('http-proxy')
Cache = require('generic-cache')

model = require('./model')
cache = new Cache()


proxy = httpProxy.createProxyServer({});

portForHostname = (hostname,callback)->
  port = cache.get(hostname)
  if port
    return callback(null,port)
  model.getApplicationForHostname(hostname,(err,application)->
    return callback(err) if err
    model.portForApplication(application.id,(err,port)->
      if not err
        cache.set(hostname,port)
      callback(err,port)
    )
  )

server = http.createServer((req, res)->
  hostname = req.headers.host
  portForHostname(hostname,(err,port)->
    if err
      res.write(err.message)
      return res.end()
#    console.log('http://localhost:'+port)
    proxy.web(req, res, { target: 'http://localhost:'+port },(err)->
      if err
        res.write(err.message)
        return res.end()
    )
  )
);

server.on('upgrade', (req, socket, head)->
  proxy.ws(req, socket, head)
)

port = process.env.PORT or 3005
console.log("listening on port",port)
server.listen(port,(err)->
  console.error(err) if err
);