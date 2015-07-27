path = require('path')
expandHomeDir = require('expand-home-dir')
fs = require('fs-extra')


settingsDir = path.join(expandHomeDir('~/.deploy-server'))
filepath = path.join(settingsDir,'config.json')

fs.ensureDirSync(settingsDir)

if fs.existsSync(filepath)
  module.exports = require(filepath)

  module.exports.PORT_START_NUMBER = module.exports.PORT_START_NUMBER*1 or 42000
  module.exports.PROXY_PORT = module.exports.PROXY_PORT*1 or 80

else
  throw new Error('deploy-server not installed, please run `deploy install` first')