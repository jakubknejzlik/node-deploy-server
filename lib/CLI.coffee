pm2 = require('pm2')
fs = require('fs-extra')
fs2 = require('fs')
path = require('path')
exec = require('child_process').exec
async = require('async')

config = require('./config')
model = require('./model')
expandHomeDir = require('expand-home-dir')

reposPath = expandHomeDir(config.REPO_BASE_PATH)
buildsPath = expandHomeDir(config.BUILD_BASE_PATH)

trimFn = (x)->
  return x.trim()
thisFn = (x)->
  return x


class CLI
  constructor:()->


  startServer:(callback)->
    @isServerRunning((err,isRunning)=>
      return callback(err) if err
      return callback(new Error('server is already running')) if isRunning
      @pm2StartProcess(path.join(__dirname,'../lib/server.js'),'deploy-server',{port:config.PORT_START_NUMBER},(err)=>
        return callback(err) if err
        @pm2StartProcess(path.join(__dirname,'../lib/proxy.js'),'deploy-server-proxy',{port:config.PROXY_PORT},callback)
      )
    )

  stopServer:(callback)->
    @isServerRunning((err,isRunning)=>
      return callback(err) if err
      return callback(new Error('server is not running')) if not isRunning
      @pm2DeleteProcess('deploy-server',(err)=>
        return callback(err) if err
        @pm2DeleteProcess('deploy-server-proxy',callback)
      )
    )

  kill:(callback)->
    @pm2Run((pm2,cb)->
      pm2.killDaemon((err)->
        cb()
        callback(err)
      )
    )
  resurrect:(callback)->
    @pm2Resurrect(callback)
  startup:(callback)->
    @pm2Startup(callback)
  dump:(callback)->
    @pm2Dump(callback)

  createApplication:(name,callback)->
    model.createApplication({name:name},(err,app)=>
      return callback(err) if err
      @_createRepo(app.name,(err)->
        return callback(err) if err
        callback(null,app)
      )
    )

  deleteApplication:(app,callback)->
    @stopApplication(app,()=>
      model.deleteApplication(app,(err,app)=>
        return callback(err) if err
        @_deleteRepo(app.name,(err)=>
          return callback(err) if err
          @_deleteBuild(app.name,(err)=>
            return callback(err) if err
            callback()
          )
        )
      )
    )

  getApplications:((callback)->
    model.getApplications(callback)
  )

  startApplication:((nameOrId,callback)->
    model.getApplication(nameOrId,(err,application)=>
      return callback(err) if err
      appPath = path.join(buildsPath,application.name)
      procfilePath = path.join(appPath,'Procfile')
      if not fs.existsSync(procfilePath)
        return callback(new Error('no Procfile found'))

      fs.readFile(procfilePath,(err,procfile)=>
        return callback(err) if err
        procstring = procfile.toString()
        @_startAppWithProcFile(application,procstring,(err)=>
          return callback(err) if err
          @pm2Dump(callback)
        )
      )
    )
  )
  stopApplication:((nameOrId,callback)->
    model.getApplication(nameOrId,(err,application)=>
      return callback(err) if err
      @_stopProcesses(application,(err)=>
        return callback(err) if err
        @pm2Dump(callback)
      )
    )
  )

  _startAppWithProcFile:(application,procfile,callback)->
    @_stopProcesses(application,(err)=>
      lines = procfile.split("\n").map(trimFn).filter(thisFn)
      async.forEachSeries(lines,(line,cb)=>
        [procName,cmd] = line.split(':').map(trimFn)
        if cmd.indexOf('node ') is 0
          processName = application.name + ': ' + procName
          filepath = path.join(buildsPath,application.name,cmd.replace('node ',''))
          options = {}
          if procName is 'web'
            model.portForApplication(application.name,(err,port)=>
              options.port = port
              console.log('starting web process',processName,'port',port)
              @pm2StartProcess(filepath,processName,options,cb)
            )
          else
            console.log('starting worker process',processName)
            @pm2StartProcess(filepath,processName,options,cb)
        else
          console.error('unsupported command',cmd)
      ,callback)
    )

  _stopProcesses:(application,callback)->
    @isServerRunning((err,isRunning)=>
      return callback(err) if err
      return callback(new Error('server is not running')) if not isRunning
      @_getPM2Apps((err,apps)=>
        return callback(err) if err
        async.forEachSeries(apps,(app,cb)=>
          if app.name.indexOf(application.name) is 0
            console.log('stopping',app.name)
            @pm2DeleteProcess(app.pm_id,cb)
          else
            cb()
        ,callback)
      )
    )

  _getPM2Apps:(callback)->
    @pm2Run((pm2,cb)->
      pm2.list((err,apps)->
        cb((err)->
          callback(err,apps)
        )
      )
    )

  isServerRunning:(callback)->
    @_getPM2Apps((err,apps)->
      return callback(err) if err
      for app in apps
        if app.name is 'deploy-server'
          return callback(null,yes)
      callback(no)
    )

  _createRepo:(name,callback)->
    repoPath = path.join(reposPath,name+'.git')
    fs.ensureDir(repoPath,(err)=>
      return callback(err) if err
      exec('git init --bare',{cwd:repoPath},(err,stdout,stderr)=>
        return callback(err) if err
        @_deployCmd((err,cmd)->
          return callback(err) if err
          content = fs.readFileSync(path.join(__dirname,'../bin/post-receive.sh')).toString()
            .replace('{BUILD_PATH}',path.join(expandHomeDir(config.BUILD_BASE_PATH),name))
            .replace('{REPO_PATH}',repoPath)
            .replace('{DEPLOY_CMD}',cmd)
          fs.writeFileSync(path.join(repoPath,'hooks/post-receive'),content)
          exec('chmod +x hooks/post-receive',{cwd:repoPath},(err,stdout,stderr)->
            callback()
          )
        )
      )
    )

  _deleteRepo:(name,callback)->
    repoPath = path.join(reposPath,name+'.git')
    fs.remove(repoPath,callback)

  _deleteBuild:(name,callback)->
    buildPath = path.join(buildsPath,name)
    fs.remove(buildPath,callback)

  _deployCmd:(callback)->
    exec('which deploy',(err,stdout,stderr)->
      if stdout
        return callback(null,stdout)
      callback(null,path.join(__dirname,'../bin/deploy.js'))
    )






  getDomainsForApplication:(appNameOrID,callback)->
    model.getApplication(appNameOrID,(err,application)=>
      return callback(err) if err
      application.getDomains({raw:yes}).then((domains)=>
        callback(null,domains)
      ).catch(callback)
    )
  addDomainToApplication:(appNameOrID,domain,callback)->
    model.addDomainToApplication(appNameOrID,domain,callback)
  removeDomainFromApplication:(appNameOrID,domain,callback)->
    model.removeDomainFromApplication(appNameOrID,domain,callback)


  getUsers:(callback)->
    model.getUsers(callback)
  addUser:(username,password,callback)->
    model.addUser(username,password,callback)
  removeUser:(username,callback)->
    model.removeUser(username,callback)



  getProcesses:(callback)->
    @pm2Run((pm2,cb)->
      pm2.list((err,processes)->
        cb()
        callback(err,processes)
      )
    )



  pm2Run:(fn)->
    pm2.connect(()->
      fn(pm2,(cb)->
        pm2.disconnect(cb)
      )
    )

  pm2StartProcess:(file,name,options,callback)->
    options = options or {}
    options.name = name
    @pm2Run((pm2,cb)->
      pm2.start(file,options,(err,app)->
        cb()
        callback(err)
      )
    )
  pm2DeleteProcess:(name,callback)->
    @pm2Run((pm2,cb)->
      pm2.delete(name,(err)->
        cb()
        callback(err)
      )
    )
  pm2Startup:(callback)->
    callback(new Error("please run following commands to create startup script \nsudo PM2_home=\"" + process.env.PM2_HOME + "\" pm2 startup;\nsudo chown " + process.env.USER + ' ' + path.join(process.env.PM2_HOME,'dump.pm2') + ';'))
#    @pm2Run((pm2,cb)->
#      console.log('sss')
#      pm2.startup(null,(err)->
#        console.log('xxx')
#        cb()
#        callback(err)
#      )
#    )
  pm2Dump:(callback)->
    @pm2Run((pm2,cb)->
      pm2.dump((err)->
        cb()
        callback(err)
      )
    )
  pm2Resurrect:(callback)->
    @pm2Run((pm2,cb)->
      pm2.resurrect((err)->
        cb()
        callback(err)
      )
    )

module.exports = new CLI()