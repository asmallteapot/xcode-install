require 'claide'
require 'xcode/install/version'

module XcodeInstall
  class PlainInformative < StandardError
    include CLAide::InformativeError
  end

  class Informative < PlainInformative
    def message
      "[!] #{super}".ansi.red
    end
  end

  class Command < CLAide::Command
    require 'xcode/install/commands/cleanup'
    require 'xcode/install/commands/cli'
    require 'xcode/install/commands/install'
    require 'xcode/install/commands/installed'
    require 'xcode/install/commands/list'
    require 'xcode/install/commands/select'
    require 'xcode/install/commands/selected'
    require 'xcode/install/commands/uninstall'
    require 'xcode/install/commands/update'
    require 'xcode/install/commands/simulators'

    self.abstract_command = true
    self.command = 'xcversion'
    self.version = VERSION
    self.description = 'Xcode installation manager.'
  end
end
