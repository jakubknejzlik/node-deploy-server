express = require('express')
pushover = require('pushover')
expandHomeDir = require('expand-home-dir')
config = require('./config')
CLI = require('./CLI')
config = require('./config')

model = require('./model')

auth = require('http-auth');
basic = auth.basic({
  realm: "GIT deploy-server"
}, (username, password, callback)->
  model.authorizeUser(username,password,(err,authorized)->
    return callback(no) if err
    callback(authorized)
  )
)

app = new express()

repos = pushover(expandHomeDir(config.REPO_BASE_PATH),{
  autoCreate:no
})

app.use((req,res,next)->
  model.getUsers((err,users)->
    return callback(err) if err
    return next() if users.length is 0
    auth.connect(basic)(req,res,next)
  )
)

app.use((req,res,next)->
  repos.handle(req,res)
)
port = process.env.PORT or 5000
app.listen(port,(err)->
  if err
    return console.error(port,err)
  console.log('listening on',port)
)