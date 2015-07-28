Sequelize = require('sequelize')
expandHomeDir = require('expand-home-dir')
Q = require('q')
fs = require('fs-extra')
logger = require('./logger')
config = require('./config')
md5 = require('md5')
validator = require('validator')
async = require('async')

storagePath = expandHomeDir(config.DATABASE_PATH)

logger.debug('db path',storagePath)
db = new Sequelize('sqlite://',{logging:logger.debug,storage:storagePath})

Application = db.define('Application',{
  name:{
    type:Sequelize.STRING,
    unique:yes
  },
  config:{
    type:Sequelize.TEXT('medium')
    get:(()->
      return JSON.parse(@getDataValue('config')) or {}
    )
    set:((value)->
      @setDataValue('config',JSON.stringify(value))
    )
  }
})

Domain = db.define('Domain',{
  name:{
    type:Sequelize.STRING,
    unique:yes
  }
})

User = db.define('User',{
  username:{
    type:Sequelize.STRING,
    unique:yes
  },
  password:Sequelize.STRING
})

Application.hasMany(Domain,{onDelete:'cascade'})
Domain.belongsTo(Application)
User.belongsToMany(Application,{through:'UserApplications'})
Application.belongsToMany(User,{through:'UserApplications'})

class Model

  ensureStorage:()->
    return Q.fcall(()=>
      deferred = Q.defer()
      fs.exists(storagePath,(exists)->
        if exists
          deferred.resolve()
        else
          db.sync().then(deferred.resolve).catch(deferred.reject)
      )
      return deferred.promise
    )

  sync:(options,callback)->
    db.sync(options).then(callback).catch(callback)

  createApplication:(data,callback)->
    @ensureStorage().then(()->
      return Application.create(data)
    ).then((app)->
      callback(null,app)
    ).catch(callback)

  deleteApplication:(appNameOrID,callback)->
    application = null
    @ensureStorage().then(()->
      orStatement = []
      if typeof appNameOrID is 'string'
        orStatement.push({name:appNameOrID})
      if validator.isInt(appNameOrID)
        orStatement.push({id:appNameOrID})
      return Application.findOne({where:{$or:orStatement}}).then((app)->
        application = app
        if not app
          throw new Error('application ' + appNameOrID + ' not found')
        return app.destroy()
      )
    ).then(()->
      callback(null,application)
    ).catch(callback)

  getApplications:(callback)->
    @ensureStorage().then(()->
      return Application.findAll().then((apps)=>
        callback(null,apps)
      ).catch(callback)
    )

  getApplication:(appNameOrID,callback)->
    @ensureStorage().then(()->
      orStatement = []
      if typeof appNameOrID is 'string'
        orStatement.push({name:appNameOrID})
      if validator.isInt(appNameOrID)
        orStatement.push({id:appNameOrID})
      return Application.findOne({where:{$or:orStatement}}).then((app)=>
        return callback(new Error('app ' + appNameOrID + ' not found')) if not app
        callback(null,app)
      ).catch(callback)
    )

  portForApplication:(appNameOrID,callback)->
    @getApplication(appNameOrID,(err,application)->
      return callback(err) if err
      callback(null,config.PORT_START_NUMBER + application.id + 5)
    )



  getApplicationForHostname:(hostname,callback)->
    Domain.findAll({order:[[Sequelize.fn('length',Sequelize.col('name')),'DESC']]}).then((domains)->
      domain = null
      for dom in domains
        regexp = new RegExp(dom.name.replace(/\./,'\\.').replace(/\*/,'.*').replace(/\?/,'.'),'i')
        if regexp.test(hostname)
          domain = dom
          break

      return callback(new Error('no application found for domain ' + domain)) if not domain
      domain.getApplication().then((app)->
        callback(null,app)
      ).catch(callback)
    ).catch(callback)

  addDomainToApplication:(appNameOrID,domain,callback)->
    @getApplication(appNameOrID,(err,application)->
      return callback(err) if err
      dom = Domain.create({name:domain}).then((dom)->
        dom.setApplication(application).then((domain)->
          callback(null,domain)
        ).catch(callback)
      ).catch(callback)
    )
  removeDomainFromApplication:(appNameOrID,domainOrId,callback)->
    @getApplication(appNameOrID,(err,application)->
      return callback(err) if err
      orStatement = []
      if typeof domainOrId is 'string'
        orStatement.push({name:domainOrId})
      if validator.isInt(domainOrId)
        orStatement.push({id:domainOrId})
      application.getDomains({where:{$or:orStatement}}).then((domains)->
        return callback(new Error('domain ' + domainOrId + ' not found')) if domains.length is 0
        domain = domains[0]
        domain.destroy().then(()->
          callback()
        ).catch(callback)
      ).catch(callback)
    )

  getUsers:(callback)->
    User.findAll().then((users)->
      callback(null,users)
    ).catch(callback)
  addUser:(username,password,callback)->
    User.create({username:username,password:md5(password)}).then((user)->
      callback(null,user)
    ).catch(callback)
  removeUser:(username,callback)->
    User.findOne({where:{username:username}}).then((user)->
      return callback(new Error('user ' + username + ' not found')) if not user
      user.destroy().then(()->
        callback(null,user)
      ).catch(callback)
    ).catch(callback)
  authorizeUser:(username,password,callback)->
    User.findOne({where:{username:username}}).then((user)->
      return callback(null,no) if not user
      callback(null,user.password is md5(password))
    ).catch(callback)




module.exports = new Model()