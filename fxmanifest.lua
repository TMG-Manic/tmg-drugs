fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'TMG_Manic'
description 'Drugs System Imrpoved'
version '1.0.0'

shared_scripts {
    'config.lua',
    '@tmg-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    '@PolyZone/ComboZone.lua',
    'client/main.lua'
}

server_scripts {
    'server/deliveries.lua',
    'server/cornerselling.lua'
}
