return {
  'mikesmithgh/kitty-scrollback.nvim',
  version = '^9.0.0',
  lazy = true,
  cmd = {
    'KittyScrollbackGenerateKittens',
    'KittyScrollbackCheckHealth',
    'KittyScrollbackGenerateCommandLineEditing',
  },
  event = 'User KittyScrollbackLaunch',
  opts = {},
}
