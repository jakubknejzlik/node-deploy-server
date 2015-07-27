#!/bin/bash
DEPLOY={DEPLOY_CMD}
REPO_PATH={REPO_PATH}
BUILD_PATH={BUILD_PATH}
BUILD_TMP_PATH=$(dirname $BUILD_PATH)/$(basename $BUILD_PATH)_tmp

rm -r $BUILD_TMP_PATH

git clone $REPO_PATH $BUILD_TMP_PATH


pushd $BUILD_TMP_PATH
npm install
popd

rm -r $BUILD_PATH
mv $BUILD_TMP_PATH $BUILD_PATH



pushd $BUILD_PATH


    appname=$(basename $BUILD_PATH)
#    PM2_HOME='.deploy-server' pm2 delete $appname
#    PM2_HOME='.deploy-server' pm2 start index.js -n $appname -f
    $DEPLOY apps:start $appname

popd