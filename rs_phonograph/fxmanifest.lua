fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'Phonograph script '
author 'riversafe'
version '2.0'

ui_page {
	'html/index.html'
}

files {
	'html/index.html',
    'html/play.png',
    'html/stop.png',
    'html/loop.png',
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}