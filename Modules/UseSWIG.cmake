# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

#[=======================================================================[.rst:
UseSWIG
-------

Defines the following macros for use with SWIG:

.. command:: swig_add_library

  Define swig module with given name and specified language::

    swig_add_library(<name>
                     [TYPE <SHARED|MODULE|STATIC|USE_BUILD_SHARED_LIBS>]
                     LANGUAGE <language>
                     SOURCES <file>...
                     )

  The variable ``SWIG_MODULE_<name>_REAL_NAME`` will be set to the name
  of the swig module target library.

.. command:: swig_link_libraries

  Link libraries to swig module::

    swig_link_libraries(<name> [ libraries ])

Source file properties on module files can be set before the invocation
of the ``swig_add_library`` macro to specify special behavior of SWIG:

``CPLUSPLUS``
  Call SWIG in c++ mode.  For example:

  .. code-block:: cmake

    set_property(SOURCE mymod.i PROPERTY CPLUSPLUS ON)
    swig_add_library(mymod LANGUAGE python SOURCES mymod.i)

``SWIG_FLAGS``
  Add custom flags to the SWIG executable.


``SWIG_MODULE_NAME``
  Specify the actual import name of the module in the target language.
  This is required if it cannot be scanned automatically from source
  or different from the module file basename.  For example:

  .. code-block:: cmake

    set_property(SOURCE mymod.i PROPERTY SWIG_MODULE_NAME mymod_realname)

Some variables can be set to specify special behavior of SWIG:

``CMAKE_SWIG_FLAGS``
  Add flags to all swig calls.

``CMAKE_SWIG_OUTDIR``
  Specify where to write the language specific files (swig ``-outdir`` option).

``SWIG_OUTFILE_DIR``
  Specify where to write the output file (swig ``-o`` option).
  If not specified, ``CMAKE_SWIG_OUTDIR`` is used.

``SWIG_MODULE_<name>_EXTRA_DEPS``
  Specify extra dependencies for the generated module for ``<name>``.
#]=======================================================================]

set(SWIG_CXX_EXTENSION "cxx")
set(SWIG_EXTRA_LIBRARIES "")

set(SWIG_PYTHON_EXTRA_FILE_EXTENSIONS ".py")
set(SWIG_JAVA_EXTRA_FILE_EXTENSIONS ".java" "JNI.java")

#
# For given swig module initialize variables associated with it
#
macro(SWIG_MODULE_INITIALIZE name language)
  string(TOUPPER "${language}" swig_uppercase_language)
  string(TOLOWER "${language}" swig_lowercase_language)
  set(SWIG_MODULE_${name}_LANGUAGE "${swig_uppercase_language}")
  set(SWIG_MODULE_${name}_SWIG_LANGUAGE_FLAG "${swig_lowercase_language}")

  set(SWIG_MODULE_${name}_REAL_NAME "${name}")
  if (";${CMAKE_SWIG_FLAGS};" MATCHES ";-noproxy;")
    set (SWIG_MODULE_${name}_NOPROXY TRUE)
  endif ()
  if("x${SWIG_MODULE_${name}_LANGUAGE}" STREQUAL "xUNKNOWN")
    message(FATAL_ERROR "SWIG Error: Language \"${language}\" not found")
  elseif("x${SWIG_MODULE_${name}_LANGUAGE}" STREQUAL "xPYTHON" AND NOT SWIG_MODULE_${name}_NOPROXY)
    # swig will produce a module.py containing an 'import _modulename' statement,
    # which implies having a corresponding _modulename.so (*NIX), _modulename.pyd (Win32),
    # unless the -noproxy flag is used
    set(SWIG_MODULE_${name}_REAL_NAME "_${name}")
  elseif("x${SWIG_MODULE_${name}_LANGUAGE}" STREQUAL "xPERL")
    set(SWIG_MODULE_${name}_EXTRA_FLAGS "-shadow")
  endif()
endmacro()

#
# For a given language, input file, and output file, determine extra files that
# will be generated. This is internal swig macro.
#

macro(SWIG_GET_EXTRA_OUTPUT_FILES language outfiles generatedpath infile)
  set(${outfiles} "")
  get_source_file_property(SWIG_GET_EXTRA_OUTPUT_FILES_module_basename
    ${infile} SWIG_MODULE_NAME)
  if(SWIG_GET_EXTRA_OUTPUT_FILES_module_basename STREQUAL "NOTFOUND")

    # try to get module name from "%module foo" syntax
    if ( EXISTS ${infile} )
      file ( STRINGS ${infile} _MODULE_NAME REGEX "[ ]*%module[ ]*[a-zA-Z0-9_]+.*" )
    endif ()
    if ( _MODULE_NAME )
      string ( REGEX REPLACE "[ ]*%module[ ]*([a-zA-Z0-9_]+).*" "\\1" _MODULE_NAME "${_MODULE_NAME}" )
      set(SWIG_GET_EXTRA_OUTPUT_FILES_module_basename "${_MODULE_NAME}")

    else ()
      # try to get module name from "%module (options=...) foo" syntax
      if ( EXISTS ${infile} )
        file ( STRINGS ${infile} _MODULE_NAME REGEX "[ ]*%module[ ]*\\(.*\\)[ ]*[a-zA-Z0-9_]+.*" )
      endif ()
      if ( _MODULE_NAME )
        string ( REGEX REPLACE "[ ]*%module[ ]*\\(.*\\)[ ]*([a-zA-Z0-9_]+).*" "\\1" _MODULE_NAME "${_MODULE_NAME}" )
        set(SWIG_GET_EXTRA_OUTPUT_FILES_module_basename "${_MODULE_NAME}")

      else ()
        # fallback to file basename
        get_filename_component(SWIG_GET_EXTRA_OUTPUT_FILES_module_basename ${infile} NAME_WE)
      endif ()
    endif ()

  endif()
  foreach(it ${SWIG_${language}_EXTRA_FILE_EXTENSIONS})
    set(extra_file "${generatedpath}/${SWIG_GET_EXTRA_OUTPUT_FILES_module_basename}${it}")
    list(APPEND ${outfiles} ${extra_file})
    # Treat extra outputs as plain files regardless of language.
    set_property(SOURCE "${extra_file}" PROPERTY LANGUAGE "")
  endforeach()
endmacro()

#
# Take swig (*.i) file and add proper custom commands for it
#
macro(SWIG_ADD_SOURCE_TO_MODULE name outfiles infile)
  set(swig_full_infile ${infile})
  get_filename_component(swig_source_file_name_we "${infile}" NAME_WE)
  get_source_file_property(swig_source_file_generated ${infile} GENERATED)
  get_source_file_property(swig_source_file_cplusplus ${infile} CPLUSPLUS)
  get_source_file_property(swig_source_file_flags ${infile} SWIG_FLAGS)
  if("${swig_source_file_flags}" STREQUAL "NOTFOUND")
    set(swig_source_file_flags "")
  endif()
  get_filename_component(swig_source_file_fullname "${infile}" ABSOLUTE)

  # If CMAKE_SWIG_OUTDIR was specified then pass it to -outdir
  if(CMAKE_SWIG_OUTDIR)
    set(swig_outdir ${CMAKE_SWIG_OUTDIR})
  else()
    set(swig_outdir ${CMAKE_CURRENT_BINARY_DIR})
  endif()

  if(SWIG_OUTFILE_DIR)
    set(swig_outfile_dir ${SWIG_OUTFILE_DIR})
  else()
    set(swig_outfile_dir ${swig_outdir})
  endif()

  if (NOT SWIG_MODULE_${name}_NOPROXY)
    SWIG_GET_EXTRA_OUTPUT_FILES(${SWIG_MODULE_${name}_LANGUAGE}
      swig_extra_generated_files
      "${swig_outdir}"
      "${swig_source_file_fullname}")
  endif()
  set(swig_generated_file_fullname
    "${swig_outfile_dir}/${swig_source_file_name_we}")
  # add the language into the name of the file (i.e. TCL_wrap)
  # this allows for the same .i file to be wrapped into different languages
  string(APPEND swig_generated_file_fullname
    "${SWIG_MODULE_${name}_LANGUAGE}_wrap")

  if(swig_source_file_cplusplus)
    string(APPEND swig_generated_file_fullname
      ".${SWIG_CXX_EXTENSION}")
  else()
    string(APPEND swig_generated_file_fullname
      ".c")
  endif()

  #message("Full path to source file: ${swig_source_file_fullname}")
  #message("Full path to the output file: ${swig_generated_file_fullname}")
  get_directory_property(cmake_include_directories INCLUDE_DIRECTORIES)
  list(REMOVE_DUPLICATES cmake_include_directories)
  set(swig_include_dirs)
  foreach(it ${cmake_include_directories})
    set(swig_include_dirs ${swig_include_dirs} "-I${it}")
  endforeach()

  set(swig_special_flags)
  # default is c, so add c++ flag if it is c++
  if(swig_source_file_cplusplus)
    set(swig_special_flags ${swig_special_flags} "-c++")
  endif()
  if("x${SWIG_MODULE_${name}_LANGUAGE}" STREQUAL "xCSHARP")
    if(NOT ";${swig_source_file_flags};${CMAKE_SWIG_FLAGS};" MATCHES ";-dllimport;")
      # This makes sure that the name used in the generated DllImport
      # matches the library name created by CMake
      set(SWIG_MODULE_${name}_EXTRA_FLAGS "-dllimport;${name}")
    endif()
  endif()
  set(swig_extra_flags)
  if(SWIG_MODULE_${name}_EXTRA_FLAGS)
    set(swig_extra_flags ${swig_extra_flags} ${SWIG_MODULE_${name}_EXTRA_FLAGS})
  endif()
  # IMPLICIT_DEPENDS below can not handle situations where a dependent file is
  # removed. We need an extra step with timestamp and custom target, see #16830
  # As this is needed only for Makefile generator do it conditionally
  if(CMAKE_GENERATOR MATCHES "Make")
    get_filename_component(swig_generated_timestamp
      "${swig_generated_file_fullname}" NAME_WE)
    set(swig_gen_target gen_${swig_generated_timestamp})
    set(swig_generated_timestamp
      "${swig_outdir}/${swig_generated_timestamp}.stamp")
    set(swig_custom_output ${swig_generated_timestamp})
    set(swig_custom_products
      BYPRODUCTS "${swig_generated_file_fullname}" ${swig_extra_generated_files})
    set(swig_timestamp_command
      COMMAND ${CMAKE_COMMAND} -E touch ${swig_generated_timestamp})
  else()
    set(swig_custom_output
      "${swig_generated_file_fullname}" ${swig_extra_generated_files})
    set(swig_custom_products)
    set(swig_timestamp_command)
  endif()
  add_custom_command(
    OUTPUT ${swig_custom_output}
    ${swig_custom_products}
    # Let's create the ${swig_outdir} at execution time, in case dir contains $(OutDir)
    COMMAND ${CMAKE_COMMAND} -E make_directory ${swig_outdir}
    ${swig_timestamp_command}
    COMMAND "${SWIG_EXECUTABLE}"
    ARGS "-${SWIG_MODULE_${name}_SWIG_LANGUAGE_FLAG}"
    ${swig_source_file_flags}
    ${CMAKE_SWIG_FLAGS}
    -outdir ${swig_outdir}
    ${swig_special_flags}
    ${swig_extra_flags}
    ${swig_include_dirs}
    -o "${swig_generated_file_fullname}"
    "${swig_source_file_fullname}"
    MAIN_DEPENDENCY "${swig_source_file_fullname}"
    DEPENDS ${SWIG_MODULE_${name}_EXTRA_DEPS}
    IMPLICIT_DEPENDS CXX "${swig_source_file_fullname}"
    COMMENT "Swig source")
  if(CMAKE_GENERATOR MATCHES "Make")
    add_custom_target(${swig_gen_target} DEPENDS ${swig_generated_timestamp})
  endif()
  unset(swig_generated_timestamp)
  unset(swig_custom_output)
  unset(swig_custom_products)
  unset(swig_timestamp_command)
  set_source_files_properties("${swig_generated_file_fullname}" ${swig_extra_generated_files}
    PROPERTIES GENERATED 1)
  set(${outfiles} "${swig_generated_file_fullname}" ${swig_extra_generated_files})
endmacro()

#
# Create Swig module
#
macro(SWIG_ADD_MODULE name language)
  message(DEPRECATION "SWIG_ADD_MODULE is deprecated. Use SWIG_ADD_LIBRARY instead.")
  swig_add_library(${name}
                   LANGUAGE ${language}
                   TYPE MODULE
                   SOURCES ${ARGN})
endmacro()


macro(SWIG_ADD_LIBRARY name)
  set(options "")
  set(oneValueArgs LANGUAGE
                   TYPE)
  set(multiValueArgs SOURCES)
  cmake_parse_arguments(_SAM "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT DEFINED _SAM_LANGUAGE)
    message(FATAL_ERROR "SWIG_ADD_LIBRARY: Missing LANGUAGE argument")
  endif()

  if(NOT DEFINED _SAM_SOURCES)
    message(FATAL_ERROR "SWIG_ADD_LIBRARY: Missing SOURCES argument")
  endif()

  if(NOT DEFINED _SAM_TYPE)
    set(_SAM_TYPE MODULE)
  elseif("${_SAM_TYPE}" STREQUAL "USE_BUILD_SHARED_LIBS")
    unset(_SAM_TYPE)
  endif()

  swig_module_initialize(${name} ${_SAM_LANGUAGE})

  set(swig_dot_i_sources)
  set(swig_other_sources)
  foreach(it ${_SAM_SOURCES})
    if(${it} MATCHES "\\.i$")
      set(swig_dot_i_sources ${swig_dot_i_sources} "${it}")
    else()
      set(swig_other_sources ${swig_other_sources} "${it}")
    endif()
  endforeach()

  set(swig_generated_sources)
  foreach(it ${swig_dot_i_sources})
    SWIG_ADD_SOURCE_TO_MODULE(${name} swig_generated_source ${it})
    set(swig_generated_sources ${swig_generated_sources} "${swig_generated_source}")
  endforeach()
  get_directory_property(swig_extra_clean_files ADDITIONAL_MAKE_CLEAN_FILES)
  set_directory_properties(PROPERTIES
    ADDITIONAL_MAKE_CLEAN_FILES "${swig_extra_clean_files};${swig_generated_sources}")
  add_library(${SWIG_MODULE_${name}_REAL_NAME}
    ${_SAM_TYPE}
    ${swig_generated_sources}
    ${swig_other_sources})
  if(CMAKE_GENERATOR MATCHES "Make")
    # see IMPLICIT_DEPENDS above
    add_dependencies(${SWIG_MODULE_${name}_REAL_NAME} ${swig_gen_target})
  endif()
  if("${_SAM_TYPE}" STREQUAL "MODULE")
    set_target_properties(${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES NO_SONAME ON)
  endif()
  string(TOLOWER "${_SAM_LANGUAGE}" swig_lowercase_language)
  if ("${swig_lowercase_language}" STREQUAL "octave")
    set_target_properties(${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES PREFIX "")
    set_target_properties(${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES SUFFIX ".oct")
  elseif ("${swig_lowercase_language}" STREQUAL "go")
    set_target_properties(${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES PREFIX "")
  elseif ("${swig_lowercase_language}" STREQUAL "java")
    if (APPLE)
        # In java you want:
        #      System.loadLibrary("LIBRARY");
        # then JNI will look for a library whose name is platform dependent, namely
        #   MacOS  : libLIBRARY.jnilib
        #   Windows: LIBRARY.dll
        #   Linux  : libLIBRARY.so
        set_target_properties (${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES SUFFIX ".jnilib")
      endif ()
  elseif ("${swig_lowercase_language}" STREQUAL "lua")
    if("${_SAM_TYPE}" STREQUAL "MODULE")
      set_target_properties(${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES PREFIX "")
    endif()
  elseif ("${swig_lowercase_language}" STREQUAL "python")
    # this is only needed for the python case where a _modulename.so is generated
    set_target_properties(${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES PREFIX "")
    # Python extension modules on Windows must have the extension ".pyd"
    # instead of ".dll" as of Python 2.5.  Older python versions do support
    # this suffix.
    # http://docs.python.org/whatsnew/ports.html#SECTION0001510000000000000000
    # <quote>
    # Windows: .dll is no longer supported as a filename extension for extension modules.
    # .pyd is now the only filename extension that will be searched for.
    # </quote>
    if(WIN32 AND NOT CYGWIN)
      set_target_properties(${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES SUFFIX ".pyd")
    endif()
  elseif ("${swig_lowercase_language}" STREQUAL "r")
    set_target_properties(${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES PREFIX "")
  elseif ("${swig_lowercase_language}" STREQUAL "ruby")
    # In ruby you want:
    #      require 'LIBRARY'
    # then ruby will look for a library whose name is platform dependent, namely
    #   MacOS  : LIBRARY.bundle
    #   Windows: LIBRARY.dll
    #   Linux  : LIBRARY.so
    set_target_properties (${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES PREFIX "")
    if (APPLE)
      set_target_properties (${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES SUFFIX ".bundle")
    endif ()
  else()
    # assume empty prefix because we expect the module to be dynamically loaded
    set_target_properties (${SWIG_MODULE_${name}_REAL_NAME} PROPERTIES PREFIX "")
  endif ()
endmacro()

#
# Like TARGET_LINK_LIBRARIES but for swig modules
#
macro(SWIG_LINK_LIBRARIES name)
  if(SWIG_MODULE_${name}_REAL_NAME)
    target_link_libraries(${SWIG_MODULE_${name}_REAL_NAME} ${ARGN})
  else()
    message(SEND_ERROR "Cannot find Swig library \"${name}\".")
  endif()
endmacro()
