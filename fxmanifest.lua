fx_version 'cerulean'
game 'rdr3'
lua54 'yes'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author '@mhdbinshad'
description 'Zone Top 3 Kills Leaderboard'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/cordmanager.html',
    'html/cordmanager.css',
    'html/cordmanager.js',
    'html/*.gif',
    'html/*.png',
    'html/RDRCatalogueBold-Bold.woff'
}

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- Added SQL Library
    'server.lua'
}

client_scripts {
    'client.lua'
}

dependency 'vorp_core'
dependency 'oxmysql' -- Added SQL Dependency
