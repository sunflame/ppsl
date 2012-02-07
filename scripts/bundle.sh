#!/bin/bash

NAME=${1:-latest}
DIR=${2:-ppsl}
tar cvzf ${DIR}/packages/${NAME}.tgz ${DIR}/ --exclude=.git --exclude=packages
