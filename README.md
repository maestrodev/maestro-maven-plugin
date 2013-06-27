maestro-mavan-plugin
====================

A Maestro Plugin that provides integration with Maven

Task Parameters
---------------

* "Path"

  A valid path to a directory containing the Maven pom.xml file.

* "Goals" (optional)

  Default: ""
  
  Maven goals to execute.  Leaving blank will cause default goal(s) in pom.xml to run.

* "Environment" (optional)

  Default: ""
  
  Environment string to pass to command shell immediately prior to the Maven executable.

* "Settingsfile" (optional)

  Default: ""
  
  Location of the settings.xml for Maven to use.

* "Profiles" (optional)

  Default: [] (empty)

  Maven profile(s) to activate.  These are passed to Maven using '-P'

* "Properties"

  Default: [] (empty)

  Any properties to pass to maven.  These are passed to Maven using '-D'
