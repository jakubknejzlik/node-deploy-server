#!/usr/bin/env node

'use strict';

var expandHomeDir = require('expand-home-dir');

process.env.PM2_HOME = expandHomeDir('~/.deploy-server');

var path = require('path');

var pm2 = require('pm2');
var program = require('commander');
var promptly = require('promptly');
var pkg = require('../package.json');
var async = require('async');
var fs = require('fs-extra');
var exec = require('child_process').exec;

var getModel = function(){
    return require('../lib/model')
}
var getCLI = function(){
    return require('../lib/CLI')
}

program
    .version(pkg.version)


var pm2Run = function(fn){
    pm2.connect(function(){
        fn(pm2,function(callback){
            pm2.disconnect(callback)
        })
    })
}

var printError = function(err){
    console.error(err.message || err);
}

var areYouSure = function(callback){
    promptly.prompt('Are you sure?(y/n):',function(err,result){
        callback(err,result.toLowerCase() == 'y')
    })
}

program.command('install')
    .description('install deploy-server')
    .action(function(){
        var prompts = [
            {key:'DATABASE_PATH',name:'Database path',default:'~/.deploy-server/db.sqlite'},
            {key:'REPO_BASE_PATH',name:'Repositories path',default:'~/.deploy-server/repos/'},
            {key:'BUILD_BASE_PATH',name:'Builds path',default:'~/.deploy-server/builds/'},
            {key:'PORT_START_NUMBER',name:'Start port number for web processes',default:'42000'},
            {key:'PROXY_PORT',name:'Public port (for proxy – port 80 requires root access)',default:'80'}
        ];
        var data = {};
        async.forEachSeries(prompts,function(p,cb){
            promptly.prompt(p.name + '(default: '+p.default+'):',{default:p.default},function(err,result){
                if(err){
                    printError(err);
                    return err.retry();
                }
                data[p.key] = result || p.default;
                cb();
            })
        },function(err){
            fs.ensureDirSync(expandHomeDir('~/.deploy-server/'));
            fs.writeFileSync(expandHomeDir('~/.deploy-server/config.json'),JSON.stringify(data));
            promptly.prompt('Force sync model? (y/n):',function(err,result){
                getModel().sync({force:result.toLowerCase() == 'y'},function(){
                    console.log('model synched')
                })
            })
        });
    })

program.command('upgrade')
    .description('stop server, upgrade to newest version and start')
    .action(function(){
        console.log('dumping processes');
        getCLI().dump(function(err){
            if(err)return printError(err);
            console.log('terminating processes');
            getCLI().kill(function(err){
                if(err)return printError(err);
                console.log('updating source files');
                exec('npm update -g deploy-server',function(err,stdout,stderr){
                    if(err)return printError(err);
                    console.log('resurrecting');
                    getCLI().resurrect(function(err){
                        if(err)return printError(err);
                        console.log('successfully upgraded');
                        process.exit();
                    })
                })
            })
        })
    })

program.command('kill')
    .description('kill whole server and all apps')
    .action(function(){
        areYouSure(function(err,ok){
            if(ok){
                getCLI().kill(function(err){
                    if(err)printError(err);
                    else console.log('killed');
                    process.exit()
                })
            }
        })
    })
program.command('resurrect')
    .description('resurrect server and all apps')
    .action(function(){
        getCLI().resurrect(function(err){
            if(err)printError(err);
            else console.log('resurrected');
        })
    })
program.command('startup')
    .description('generate startup script')
    .action(function(){
        getCLI().dump(function(err){
            if(err)return printError(err)
            getCLI().startup(function(err){
                if(err)printError(err);
                else console.log('startup script generated');
            })
        })
    })



program.command('server:start')
    .description('start deploy-server')
    .action(function(){
        getCLI().startServer(function(err){
            if(err)return printError(err);
            else console.log('deploy-server started, proxy listening on',require('../lib/config').PROXY_PORT);
        })
    })
program.command('server:stop')
    .description('stop deploy-server')
    .action(function(){
        getCLI().stopServer(function(err){
            if(err)printError(err);
            else console.log('deploy-server stopped');
        })
    })
program.command('server:restart')
    .description('restart deploy-server')
    .action(function(){
        console.log('stopping server');
        getCLI().stopServer(function(err){
            if(err)return printError(err);
            console.log('starting server');
            getCLI().startServer(function(err){
                if(err)return printError(err);
                console.log('deploy-server started, proxy listening on',require('../lib/config').PROXY_PORT);
            })
        })
    })





program.command('apps')
    .description('list all applications')
    .action(function(){
        getCLI().getApplications(function(err,apps){
            if(err)return printError(err)
            if(apps.length == 0)return console.log('no applications')
            apps.forEach(function(app){
                console.log(app.id + ':',app.name)
            })
        })
    })
program.command('apps:create <application>')
    .description('create new application')
    .action(function(application){
        console.log('creating app');
        getCLI().createApplication(application,function(err){
            if(err)return printError(err);
            console.log('application',application,'created');
        })
    })
program.command('apps:delete [applications...]')
    .description('delete applications')
    .action(function(applications){
        areYouSure(function(err,ok){
            if(ok){
                async.forEachSeries(applications,function(application,cb){
                    getCLI().deleteApplication(application,function(err){
                        if(!err)console.log('application',application,'deleted');
                        cb(err);
                    })
                },function(err){
                    if(err)return printError(err);
                    console.log('all completed');
                })
            }
        })
    })
program.command('apps:start [applications...]')
    .description('start/restart applications')
    .action(function(applications){
        async.forEachSeries(applications,function(application,cb){
            getCLI().startApplication(application,function(err){
                if(err)return cb(err);
                console.log(application,'started')
                cb();
            })
        },function(err){
            if(err)return printError(err);
        })
    })
program.command('apps:stop [applications...]')
    .description('stop applications')
    .action(function(applications){
        async.forEachSeries(applications,function(application,cb){
            getCLI().stopApplication(application,function(err){
                if(err)return cb(err);
                console.log(application,'stopped')
                cb();
            })
        },function(err){
            if(err)return printError(err);
        })
    })



program.command('domains <application>')
    .description('list all application domains')
    .action(function(application){
        console.log(application)
        getCLI().getDomainsForApplication(application,function(err,domains){
            if(err)return printError(err)
            if(domains.length == 0)return console.log('no domains')
            domains.forEach(function(domain){
                console.log(domain.id + ':',domain.name)
            })
        })
    })
program.command('domains:add <application> <domain>')
    .description('assign domain to application')
    .action(function(application,domain){
        getCLI().addDomainToApplication(application,domain,function(err){
            if(err)return printError(err)
            console.log('domain',domain,'added')
        })
    })
program.command('domains:remove <application> <domain>')
    .description('remove domain from application')
    .action(function(application,domain){
        getCLI().removeDomainFromApplication(application,domain,function(err){
            if(err)return printError(err)
            console.log('domain',domain,'removed')
        })
    })


program.command('config <application>')
    .description('set application config')
    .action(function(application,configs){
        getModel().getApplication(application,function(err,application){
            if(err)return printError(err)
            var config = application.config;
            if(Object.keys(config).length == 0)console.log('no config')
            for(var key in config){
                console.log(key + '=' + config[key])
            }
        })
    })
program.command('config:set <application> [keys...]')
    .description('set application config')
    .action(function(application,configs){
        getModel().getApplication(application,function(err,application){
            if(err)return printError(err)
            var config = application.config

            configs.forEach(function(c){
                var values = c.split('=');
                config[values[0]] = values[1];
            })

            application.config = config
            application.save().then(function(){
                console.log('updated')
            }).catch(printError)
        })
    })
program.command('config:unset <application> [keys...]')
    .description('set application config')
    .action(function(application,configs){
        getModel().getApplication(application,function(err,application){
            if(err)return printError(err)
            var config = application.config

            configs.forEach(function(c){
                delete config[c];
            })

            application.config = config
            application.save().then(function(){
                console.log('updated')
            }).catch(printError)
        })
    })


program.command('users')
    .description('list all users')
    .action(function(){
        getCLI().getUsers(function(err,users){
            if(err)return printError(err)
            if(users.length == 0)console.log('no users')
            users.forEach(function(user){
                console.log(user.username)
            })
        })
    })
program.command('users:add <username> <password>')
    .description('add user')
    .action(function(username,password){
        getCLI().addUser(username,password,function(err,user){
            if(err)return printError(err)
            console.log('user added')
        })
    })
program.command('users:remove <username>')
    .description('remove user')
    .action(function(username){
        getCLI().removeUser(username,function(err,user){
            if(err)return printError(err)
            console.log('user removed')
        })
    })




program.command('ps')
    .description('remove domain from application')
    .action(function(){
        getCLI().getProcesses(function(err,processes){
            if(err)return printError(err)
            if(processes.length == 0)console.log('no processes');
            processes.forEach(function(ps){
                console.log(ps.pm_id+':',ps.name,"\t(pid:"+ps.pid,',port:'+ps.pm2_env.env.PORT,')');
            })
        })
    })



program.command('status')
    .description('display info')
    .action(function(cmd,arg){
        var config = require('../lib/config');
        getCLI().getUsers(function(err,users){
            getCLI().isServerRunning(function(err,isRunning){
                if(err)return printError(err);
                console.log('proxy port:',config.PROXY_PORT);
                console.log('git port:',config.PORT_START_NUMBER);
                console.log('server status:',isRunning?'running':'stopped');
                console.log('number of users:',users.length,'(' + (users.length == 0?'public':'private') + ')');
            })
        })
    })


program
    .command('*')
    .action(function(env){
        console.error('command',env,'not found');
        program.help();
    });

program.parse(process.argv);


//if(program.install)console.log('install');