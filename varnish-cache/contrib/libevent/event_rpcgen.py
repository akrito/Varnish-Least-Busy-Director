#!/usr/bin/env python
#
# Copyright (c) 2005 Niels Provos <provos@citi.umich.edu>
# All rights reserved.
#
# Generates marshalling code based on libevent.

import sys
import re

#
_NAME = "event_rpcgen.py"
_VERSION = "0.1"
_STRUCT_RE = '[a-z][a-z_0-9]*'

# Globals
line_count = 0

leading = re.compile(r'^\s+')
trailing = re.compile(r'\s+$')
white = re.compile(r'^\s+')
cppcomment = re.compile(r'\/\/.*$')
cppdirect = []

# Holds everything that makes a struct
class Struct:
    def __init__(self, name):
        self._name = name
        self._entries = []
        self._tags = {}
        print >>sys.stderr, '  Created struct: %s' % name

    def AddEntry(self, entry):
        if self._tags.has_key(entry.Tag()):
            print >>sys.stderr, ( 'Entry "%s" duplicates tag number '
                                  '%d from "%s" around line %d' ) % (
                entry.Name(), entry.Tag(),
                self._tags[entry.Tag()], line_count)
            sys.exit(1)
        self._entries.append(entry)
        self._tags[entry.Tag()] = entry.Name()
        print >>sys.stderr, '    Added entry: %s' % entry.Name()

    def Name(self):
        return self._name

    def EntryTagName(self, entry):
        """Creates the name inside an enumeration for distinguishing data
        types."""
        name = "%s_%s" % (self._name, entry.Name())
        return name.upper()

    def PrintIdented(self, file, ident, code):
        """Takes an array, add indentation to each entry and prints it."""
        for entry in code:
            print >>file, '%s%s' % (ident, entry)

    def PrintTags(self, file):
        """Prints the tag definitions for a structure."""
        print >>file, '/* Tag definition for %s */' % self._name
        print >>file, 'enum %s_ {' % self._name.lower()
        for entry in self._entries:
            print >>file, '  %s=%d,' % (self.EntryTagName(entry),
                                        entry.Tag())
        print >>file, '  %s_MAX_TAGS' % (self._name.upper())
        print >>file, '} %s_tags;\n' % (self._name.lower())

    def PrintForwardDeclaration(self, file):
        print >>file, 'struct %s;' % self._name

    def PrintDeclaration(self, file):
        print >>file, '/* Structure declaration for %s */' % self._name
        print >>file, 'struct %s {' % self._name
        for entry in self._entries:
            dcl = entry.Declaration()
            dcl.extend(
                entry.AssignDeclaration('(*%s_assign)' % entry.Name()))
            dcl.extend(
                entry.GetDeclaration('(*%s_get)' % entry.Name()))
            if entry.Array():
                dcl.extend(
                    entry.AddDeclaration('(*%s_add)' % entry.Name()))
            self.PrintIdented(file, '  ', dcl)
        print >>file, ''
        for entry in self._entries:
            print >>file, '  u_int8_t %s_set;' % entry.Name()
        print >>file, '};\n'

        print >>file, (
            'struct %s *%s_new();\n' % (self._name, self._name) +
            'void %s_free(struct %s *);\n' % (self._name, self._name) +
            'void %s_clear(struct %s *);\n' % (self._name, self._name) +
            'void %s_marshal(struct evbuffer *, const struct %s *);\n' % (
            self._name, self._name) +
            'int %s_unmarshal(struct %s *, struct evbuffer *);\n' % (
            self._name, self._name) +
            'int %s_complete(struct %s *);' % (self._name, self._name)
            )
        print >>file, ('void evtag_marshal_%s(struct evbuffer *, u_int8_t, '
                       'const struct %s *);') % ( self._name, self._name)
        print >>file, ('int evtag_unmarshal_%s(struct evbuffer *, u_int8_t, '
                       'struct %s *);') % ( self._name, self._name)

        # Write a setting function of every variable
        for entry in self._entries:
            self.PrintIdented(file, '', entry.AssignDeclaration(
                entry.AssignFuncName()))
            self.PrintIdented(file, '', entry.GetDeclaration(
                entry.GetFuncName()))
            if entry.Array():
                self.PrintIdented(file, '', entry.AddDeclaration(
                    entry.AddFuncName()))

        print >>file, '/* --- %s done --- */\n' % self._name

    def PrintCode(self, file):
        print >>file, ('/*\n'
                       ' * Implementation of %s\n'
                       ' */\n') % self._name

        # Creation
        print >>file, ( 'struct %s *\n' % self._name +
                        '%s_new()\n' % self._name +
                        '{\n'
                        '  struct %s *tmp;\n' % self._name +
                        '  if ((tmp = malloc(sizeof(struct %s))) == NULL) {\n'
                        '    event_warn("%%s: malloc", __func__);\n'
                        '    return (NULL);\n' % self._name +
                        '  }'
                        )
        for entry in self._entries:
            self.PrintIdented(file, '  ', entry.CodeNew('tmp'))
            print >>file, '  tmp->%s_set = 0;\n' % entry.Name()

        print >>file, ('  return (tmp);\n'
                       '}\n')

        # Adding
        for entry in self._entries:
            if entry.Array():
                self.PrintIdented(file, '', entry.CodeAdd())
            print >>file, ''
            
        # Assigning
        for entry in self._entries:
            self.PrintIdented(file, '', entry.CodeAssign())
            print >>file, ''

        # Getting
        for entry in self._entries:
            self.PrintIdented(file, '', entry.CodeGet())
            print >>file, ''
            
        # Clearing
        print >>file, ( 'void\n'
                        '%s_clear(struct %s *tmp)\n' % (
            self._name, self._name)+
                        '{'
                        )
        for entry in self._entries:
            self.PrintIdented(file, '  ', entry.CodeClear('tmp'))

        print >>file, '}\n'

        # Freeing
        print >>file, ( 'void\n'
                        '%s_free(struct %s *tmp)\n' % (
            self._name, self._name)+
                        '{'
                        )
        for entry in self._entries:
            self.PrintIdented(file, '  ', entry.CodeFree('tmp'))

        print >>file, ('  free(tmp);\n'
                       '}\n')

        # Marshaling
        print >>file, ('void\n'
                       '%s_marshal(struct evbuffer *evbuf, '
                       'const struct %s *tmp)' % (self._name, self._name) +
                       '{')
        for entry in self._entries:
            indent = '  '
            # Optional entries do not have to be set
            if entry.Optional():
                indent += '  '
                print >>file, '  if (tmp->%s_set) {' % entry.Name()
            self.PrintIdented(
                file, indent,
                entry.CodeMarshal('evbuf', self.EntryTagName(entry), 'tmp'))
            if entry.Optional():
                print >>file, '  }'

        print >>file, '}\n'
                       
        # Unmarshaling
        print >>file, ('int\n'
                       '%s_unmarshal(struct %s *tmp, '
                       ' struct evbuffer *evbuf)\n' % (
            self._name, self._name) +
                       '{\n'
                       '  u_int8_t tag;\n'
                       '  while (EVBUFFER_LENGTH(evbuf) > 0) {\n'
                       '    if (evtag_peek(evbuf, &tag) == -1)\n'
                       '      return (-1);\n'
                       '    switch (tag) {\n'
                       )
        for entry in self._entries:
            print >>file, '      case %s:\n' % self.EntryTagName(entry)
            if not entry.Array():
                print >>file, (
                    '        if (tmp->%s_set)\n'
                    '          return (-1);'
                    ) % (entry.Name())

            self.PrintIdented(
                file, '        ',
                entry.CodeUnmarshal('evbuf',
                                    self.EntryTagName(entry), 'tmp'))

            print >>file, ( '        tmp->%s_set = 1;\n' % entry.Name() +
                            '        break;\n' )
        print >>file, ( '      default:\n'
                        '        return -1;\n'
                        '    }\n'
                        '  }\n' )
        # Check if it was decoded completely
        print >>file, ( '  if (%s_complete(tmp) == -1)\n' % self._name +
                        '    return (-1);')

        # Successfully decoded
        print >>file, ( '  return (0);\n'
                        '}\n')

        # Checking if a structure has all the required data
        print >>file, (
            'int\n'
            '%s_complete(struct %s *msg)\n' % (self._name, self._name) +
            '{' )
        for entry in self._entries:
            self.PrintIdented(
                file, '  ',
                entry.CodeComplete('msg'))
        print >>file, (
            '  return (0);\n'
            '}\n' )

        # Complete message unmarshaling
        print >>file, (
            'int\n'
            'evtag_unmarshal_%s(struct evbuffer *evbuf, u_int8_t need_tag, '
            ' struct %s *msg)'
            ) % (self._name, self._name)
        print >>file, (
            '{\n'
            '  u_int8_t tag;\n'
            '  int res = -1;\n'
            '\n'
            '  struct evbuffer *tmp = evbuffer_new();\n'
            '\n'
            '  if (evtag_unmarshal(evbuf, &tag, tmp) == -1'
            ' || tag != need_tag)\n'
            '    goto error;\n'
            '\n'
            '  if (%s_unmarshal(msg, tmp) == -1)\n'
            '    goto error;\n'
            '\n'
            '  res = 0;\n'
            '\n'
            ' error:\n'
            '  evbuffer_free(tmp);\n'
            '  return (res);\n'
            '}\n' ) % self._name

        # Complete message marshaling
        print >>file, (
            'void\n'
            'evtag_marshal_%s(struct evbuffer *evbuf, u_int8_t tag, '
            'const struct %s *msg)\n' % (self._name, self._name) +
            '{\n'
            '  struct evbuffer *_buf = evbuffer_new();\n'
            '  assert(_buf != NULL);\n'
            '  evbuffer_drain(_buf, -1);\n'
            '  %s_marshal(_buf, msg);\n' % self._name +
            '  evtag_marshal(evbuf, tag, EVBUFFER_DATA(_buf), '
            'EVBUFFER_LENGTH(_buf));\n'
            '  evbuffer_free(_buf);\n'
            '}\n' )

class Entry:
    def __init__(self, type, name, tag):
        self._type = type
        self._name = name
        self._tag = int(tag)
        self._ctype = type
        self._optional = 0
        self._can_be_array = 0
        self._array = 0
        self._line_count = -1
        self._struct = None

    def SetStruct(self, struct):
        self._struct = struct

    def LineCount(self):
        assert self._line_count != -1
        return self._line_count

    def SetLineCount(self, number):
        self._line_count = number

    def Array(self):
        return self._array

    def Optional(self):
        return self._optional

    def Tag(self):
        return self._tag

    def Name(self):
        return self._name

    def Type(self):
        return self._type

    def MakeArray(self, yes=1):
        self._array = yes
        
    def MakeOptional(self):
        self._optional = 1

    def GetFuncName(self):
        return '%s_%s_get' % (self._struct.Name(), self._name)
    
    def GetDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, %s *);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code

    def CodeGet(self):
        code = [ 'int',
                 '%s_%s_get(struct %s *msg, %s *value)' % (
            self._struct.Name(), self._name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  if (msg->%s_set != 1)' % self._name,
                 '    return (-1);',
                 '  *value = msg->%s_data;' % self._name,
                 '  return (0);',
                 '}' ]
        return code
        
    def AssignFuncName(self):
        return '%s_%s_assign' % (self._struct.Name(), self._name)
    
    def AddFuncName(self):
        return '%s_%s_add' % (self._struct.Name(), self._name)
    
    def AssignDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, const %s);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code

    def CodeAssign(self):
        code = [ 'int',
                 '%s_%s_assign(struct %s *msg, const %s value)' % (
            self._struct.Name(), self._name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  msg->%s_set = 1;' % self._name,
                 '  msg->%s_data = value;' % self._name,
                 '  return (0);',
                 '}' ]
        return code

    def CodeClear(self, structname):
        code = [ '%s->%s_set = 0;' % (structname, self.Name()) ]

        return code
        
    def CodeComplete(self, structname):
        if self.Optional():
            return []
        
        code = [ 'if (!%s->%s_set)' % (structname, self.Name()),
                 '  return (-1);' ]

        return code

    def CodeFree(self, name):
        return []

    def CodeNew(self, name):
        code = [ '%s->%s_assign = %s_%s_assign;' % (
            name, self._name, self._struct.Name(), self._name ),
                 '%s->%s_get = %s_%s_get;' % (
            name, self._name, self._struct.Name(), self._name ),
        ]
        if self.Array():
            code.append(
                '%s->%s_add = %s_%s_add;' % (
                name, self._name, self._struct.Name(), self._name ) )
        return code

    def Verify(self):
        if self.Array() and not self._can_be_array:
            print >>sys.stderr, (
                'Entry "%s" cannot be created as an array '
                'around line %d' ) % (self._name, self.LineCount())
            sys.exit(1)
        if not self._struct:
            print >>sys.stderr, (
                'Entry "%s" does not know which struct it belongs to '
                'around line %d' ) % (self._name, self.LineCount())
            sys.exit(1)
        if self._optional and self._array:
            print >>sys.stderr,  ( 'Entry "%s" has illegal combination of '
                                   'optional and array around line %d' ) % (
                self._name, self.LineCount() )
            sys.exit(1)

class EntryBytes(Entry):
    def __init__(self, type, name, tag, length):
        # Init base class
        Entry.__init__(self, type, name, tag)

        self._length = length
        self._ctype = 'u_int8_t'

    def GetDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, %s **);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code
        
    def AssignDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, const %s *);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code
        
    def Declaration(self):
        dcl  = ['u_int8_t %s_data[%s];' % (self._name, self._length)]
        
        return dcl

    def CodeGet(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_get(struct %s *msg, %s **value)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  if (msg->%s_set != 1)' % name,
                 '    return (-1);',
                 '  *value = msg->%s_data;' % name,
                 '  return (0);',
                 '}' ]
        return code
        
    def CodeAssign(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_assign(struct %s *msg, const %s *value)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  msg->%s_set = 1;' % name,
                 '  memcpy(msg->%s_data, value, %s);' % (
            name, self._length),
                 '  return (0);',
                 '}' ]
        return code
        
    def CodeUnmarshal(self, buf, tag_name, var_name):
        code = [  'if (evtag_unmarshal_fixed(%s, %s, ' % (buf, tag_name) +
                  '%s->%s_data, ' % (var_name, self._name) +
                  'sizeof(%s->%s_data)) == -1) {' % (
            var_name, self._name),
                  '  event_warnx("%%s: failed to unmarshal %s", __func__);' % (
            self._name ),
                  '  return (-1);',
                  '}'
                  ]
        return code

    def CodeMarshal(self, buf, tag_name, var_name):
        code = ['evtag_marshal(%s, %s, %s->%s_data, sizeof(%s->%s_data));' % (
            buf, tag_name, var_name, self._name, var_name, self._name )]
        return code

    def CodeClear(self, structname):
        code = [ '%s->%s_set = 0;' % (structname, self.Name()),
                 'memset(%s->%s_data, 0, sizeof(%s->%s_data));' % (
            structname, self._name, structname, self._name)]

        return code
        
    def CodeNew(self, name):
        code  = ['memset(%s->%s_data, 0, sizeof(%s->%s_data));' % (
            name, self._name, name, self._name)]
        code.extend(Entry.CodeNew(self, name))
        return code

    def Verify(self):
        if not self._length:
            print >>sys.stderr, 'Entry "%s" needs a length around line %d' % (
                self._name, self.LineCount() )
            sys.exit(1)

        Entry.Verify(self)

class EntryInt(Entry):
    def __init__(self, type, name, tag):
        # Init base class
        Entry.__init__(self, type, name, tag)

        self._ctype = 'u_int32_t'

    def CodeUnmarshal(self, buf, tag_name, var_name):
        code = ['if (evtag_unmarshal_int(%s, %s, &%s->%s_data) == -1) {' % (
            buf, tag_name, var_name, self._name),
                  '  event_warnx("%%s: failed to unmarshal %s", __func__);' % (
            self._name ),
                '  return (-1);',
                '}' ] 
        return code

    def CodeMarshal(self, buf, tag_name, var_name):
        code = ['evtag_marshal_int(%s, %s, %s->%s_data);' % (
            buf, tag_name, var_name, self._name)]
        return code

    def Declaration(self):
        dcl  = ['u_int32_t %s_data;' % self._name]

        return dcl

class EntryString(Entry):
    def __init__(self, type, name, tag):
        # Init base class
        Entry.__init__(self, type, name, tag)

        self._ctype = 'char *'

    def CodeAssign(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_assign(struct %s *msg, const %s value)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  if (msg->%s_data != NULL)' % name,
                 '    free(msg->%s_data);' % name,
                 '  if ((msg->%s_data = strdup(value)) == NULL)' % name,
                 '    return (-1);',
                 '  msg->%s_set = 1;' % name,
                 '  return (0);',
                 '}' ]
        return code
        
    def CodeUnmarshal(self, buf, tag_name, var_name):
        code = ['if (evtag_unmarshal_string(%s, %s, &%s->%s_data) == -1) {' % (
            buf, tag_name, var_name, self._name),
                '  event_warnx("%%s: failed to unmarshal %s", __func__);' % (
            self._name ),
                '  return (-1);',
                '}'
                ]
        return code

    def CodeMarshal(self, buf, tag_name, var_name):
        code = ['evtag_marshal_string(%s, %s, %s->%s_data);' % (
            buf, tag_name, var_name, self._name)]
        return code

    def CodeClear(self, structname):
        code = [ 'if (%s->%s_set == 1) {' % (structname, self.Name()),
                 '  free (%s->%s_data);' % (structname, self.Name()),
                 '  %s->%s_data = NULL;' % (structname, self.Name()),
                 '  %s->%s_set = 0;' % (structname, self.Name()),
                 '}'
                 ]

        return code
        
    def CodeNew(self, name):
        code  = ['%s->%s_data = NULL;' % (name, self._name)]
        code.extend(Entry.CodeNew(self, name))
        return code

    def CodeFree(self, name):
        code  = ['if (%s->%s_data != NULL)' % (name, self._name),
                 '    free (%s->%s_data); ' % (name, self._name)]

        return code

    def Declaration(self):
        dcl  = ['char *%s_data;' % self._name]

        return dcl

class EntryStruct(Entry):
    def __init__(self, type, name, tag, refname):
        # Init base class
        Entry.__init__(self, type, name, tag)

        self._can_be_array = 1
        self._refname = refname
        self._ctype = 'struct %s' % refname

    def GetDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, %s **);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code
        
    def AssignDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, const %s *);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code
        
    def CodeGet(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_get(struct %s *msg, %s **value)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  if (msg->%s_set != 1) {' % name,
                 '    msg->%s_data = %s_new();' % (name, self._refname),
                 '    if (msg->%s_data == NULL)' % name,
                 '      return (-1);',
                 '    msg->%s_set = 1;' % name,
                 '  }',
                 '  *value = msg->%s_data;' % name,
                 '  return (0);',
                 '}' ]
        return code
        
    def CodeAssign(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_assign(struct %s *msg, const %s *value)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  struct evbuffer *tmp = NULL;',
                 '  if (msg->%s_set) {' % name,
                 '    %s_clear(msg->%s_data);' % (self._refname, name),
                 '    msg->%s_set = 0;' % name,
                 '  } else {',
                 '    msg->%s_data = %s_new();' % (name, self._refname),
                 '    if (msg->%s_data == NULL) {' % name,
                 '      event_warn("%%s: %s_new()", __func__);' % (
            self._refname),
                 '      goto error;',
                 '    }',
                 '  }',
                 '  if ((tmp = evbuffer_new()) == NULL) {',
                 '    event_warn("%s: evbuffer_new()", __func__);',
                 '    goto error;',
                 '  }',
                 '  %s_marshal(tmp, value); ' % self._refname,
                 '  if (%s_unmarshal(msg->%s_data, tmp) == -1) {' % (
            self._refname, name ),
                 '    event_warnx("%%s: %s_unmarshal", __func__);' % (
            self._refname),
                 '    goto error;',
                 '  }',
                 '  msg->%s_set = 1;' % name,
                 '  evbuffer_free(tmp);',
                 '  return (0);',
                 ' error:',
                 '  if (tmp != NULL)',
                 '    evbuffer_free(tmp);',
                 '  if (msg->%s_data != NULL) {' % name,
                 '    %s_free(msg->%s_data);' % (self._refname, name),
                 '    msg->%s_data = NULL;' % name,
                 '  }',
                 '  return (-1);',
                 '}' ]
        return code
        
    def CodeComplete(self, structname):
        if self.Optional():
            code = [ 'if (%s->%s_set && %s_complete(%s->%s_data) == -1)' % (
                structname, self.Name(),
                self._refname, structname, self.Name()),
                     '  return (-1);' ]
        else:
            code = [ 'if (%s_complete(%s->%s_data) == -1)' % (
                self._refname, structname, self.Name()),
                     '  return (-1);' ]

        return code
    
    def CodeUnmarshal(self, buf, tag_name, var_name):
        code = ['%s->%s_data = %s_new();' % (
            var_name, self._name, self._refname),
                'if (%s->%s_data == NULL)' % (var_name, self._name),
                '  return (-1);',
                'if (evtag_unmarshal_%s(%s, %s, %s->%s_data) == -1) {' % (
            self._refname, buf, tag_name, var_name, self._name),
                  '  event_warnx("%%s: failed to unmarshal %s", __func__);' % (
            self._name ),
                '  return (-1);',
                '}'
                ]
        return code

    def CodeMarshal(self, buf, tag_name, var_name):
        code = ['evtag_marshal_%s(%s, %s, %s->%s_data);' % (
            self._refname, buf, tag_name, var_name, self._name)]
        return code

    def CodeClear(self, structname):
        code = [ 'if (%s->%s_set == 1) {' % (structname, self.Name()),
                 '  %s_free(%s->%s_data);' % (
            self._refname, structname, self.Name()),
                 '  %s->%s_data = NULL;' % (structname, self.Name()),
                 '  %s->%s_set = 0;' % (structname, self.Name()),
                 '}'
                 ]

        return code
        
    def CodeNew(self, name):
        code  = ['%s->%s_data = NULL;' % (name, self._name)]
        code.extend(Entry.CodeNew(self, name))
        return code

    def CodeFree(self, name):
        code  = ['if (%s->%s_data != NULL)' % (name, self._name),
                 '    %s_free(%s->%s_data); ' % (
            self._refname, name, self._name)]

        return code

    def Declaration(self):
        dcl  = ['struct %s *%s_data;' % (self._refname, self._name)]

        return dcl

class EntryVarBytes(Entry):
    def __init__(self, type, name, tag):
        # Init base class
        Entry.__init__(self, type, name, tag)

        self._ctype = 'u_int8_t *'

    def GetDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, %s *, u_int32_t *);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code
        
    def AssignDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, const %s, u_int32_t);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code
        
    def CodeAssign(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_assign(struct %s *msg, '
                 'const %s value, u_int32_t len)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  if (msg->%s_data != NULL)' % name,
                 '    free (msg->%s_data);' % name,
                 '  msg->%s_data = malloc(len);' % name,
                 '  if (msg->%s_data == NULL)' % name,
                 '    return (-1);',
                 '  msg->%s_set = 1;' % name,
                 '  msg->%s_length = len;' % name,
                 '  memcpy(msg->%s_data, value, len);' % name,
                 '  return (0);',
                 '}' ]
        return code
        
    def CodeGet(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_get(struct %s *msg, %s *value, u_int32_t *plen)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  if (msg->%s_set != 1)' % name,
                 '    return (-1);',
                 '  *value = msg->%s_data;' % name,
                 '  *plen = msg->%s_length;' % name,
                 '  return (0);',
                 '}' ]
        return code

    def CodeUnmarshal(self, buf, tag_name, var_name):
        code = ['if (evtag_payload_length(%s, &%s->%s_length) == -1)' % (
            buf, var_name, self._name),
                '  return (-1);',
                # We do not want DoS opportunities
                'if (%s->%s_length > EVBUFFER_LENGTH(%s))' % (
            var_name, self._name, buf),
                '  return (-1);',
                'if ((%s->%s_data = malloc(%s->%s_length)) == NULL)' % (
            var_name, self._name, var_name, self._name),
                '  return (-1);',
                'if (evtag_unmarshal_fixed(%s, %s, %s->%s_data, '
                '%s->%s_length) == -1) {' % (
            buf, tag_name, var_name, self._name, var_name, self._name),
                '  event_warnx("%%s: failed to unmarshal %s", __func__);' % (
            self._name ),
                '  return (-1);',
                '}'
                ]
        return code

    def CodeMarshal(self, buf, tag_name, var_name):
        code = ['evtag_marshal(%s, %s, %s->%s_data, %s->%s_length);' % (
            buf, tag_name, var_name, self._name, var_name, self._name)]
        return code

    def CodeClear(self, structname):
        code = [ 'if (%s->%s_set == 1) {' % (structname, self.Name()),
                 '  free (%s->%s_data);' % (structname, self.Name()),
                 '  %s->%s_data = NULL;' % (structname, self.Name()),
                 '  %s->%s_length = 0;' % (structname, self.Name()),
                 '  %s->%s_set = 0;' % (structname, self.Name()),
                 '}'
                 ]

        return code
        
    def CodeNew(self, name):
        code  = ['%s->%s_data = NULL;' % (name, self._name),
                 '%s->%s_length = 0;' % (name, self._name) ]
        code.extend(Entry.CodeNew(self, name))
        return code

    def CodeFree(self, name):
        code  = ['if (%s->%s_data != NULL)' % (name, self._name),
                 '    free (%s->%s_data); ' % (name, self._name)]

        return code

    def Declaration(self):
        dcl  = ['u_int8_t *%s_data;' % self._name,
                'u_int32_t %s_length;' % self._name]

        return dcl

class EntryArray(Entry):
    def __init__(self, entry):
        # Init base class
        Entry.__init__(self, entry._type, entry._name, entry._tag)

        self._entry = entry
        self._refname = entry._refname
        self._ctype = 'struct %s' % self._refname

    def GetDeclaration(self, funcname):
        """Allows direct access to elements of the array."""
        code = [ 'int %s(struct %s *, int, %s **);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code
        
    def AssignDeclaration(self, funcname):
        code = [ 'int %s(struct %s *, int, const %s *);' % (
            funcname, self._struct.Name(), self._ctype ) ]
        return code
        
    def AddDeclaration(self, funcname):
        code = [ '%s *%s(struct %s *);' % (
            self._ctype, funcname, self._struct.Name() ) ]
        return code
        
    def CodeGet(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_get(struct %s *msg, int offset, %s **value)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  if (msg->%s_set != 1)' % name,
                 '    return (-1);',
                 '  if (offset >= msg->%s_length)' % name,
                 '    return (-1);',
                 '  *value = msg->%s_data[offset];' % name,
                 '  return (0);',
                 '}' ]
        return code
        
    def CodeAssign(self):
        name = self._name
        code = [ 'int',
                 '%s_%s_assign(struct %s *msg, int off, const %s *value)' % (
            self._struct.Name(), name,
            self._struct.Name(), self._ctype),
                 '{',
                 '  struct evbuffer *tmp = NULL;',
                 '  if (msg->%s_set != 1)' % name,
                 '    return (-1);',
                 '  if (off >= msg->%s_length)' % name,
                 '    return (-1);',
                 '',
                 '  %s_clear(msg->%s_data[off]);' % (self._refname, name),
                 '  if ((tmp = evbuffer_new()) == NULL) {',
                 '    event_warn("%s: evbuffer_new()", __func__);',
                 '    goto error;',
                 '  }',
                 '  %s_marshal(tmp, value); ' % self._refname,
                 '  if (%s_unmarshal(msg->%s_data[off], tmp) == -1) {' % (
            self._refname, name ),
                 '    event_warnx("%%s: %s_unmarshal", __func__);' % (
            self._refname),
                 '    goto error;',
                 '  }',
                 '  evbuffer_free(tmp);',
                 '  return (0);',
                 ' error:',
                 '  if (tmp != NULL)',
                 '    evbuffer_free(tmp);',
                 '  %s_clear(msg->%s_data[off]);' % (self._refname, name),
                 '  return (-1);',
                 '}' ]
        return code
        
    def CodeAdd(self):
        name = self._name
        code = [
            '%s *' % self._ctype, 
            '%s_%s_add(struct %s *msg)' % (
            self._struct.Name(), name, self._struct.Name()),
            '{',
            '  msg->%s_length++;' % name,
            '  msg->%s_data = (struct %s**)realloc(msg->%s_data, '
            '  msg->%s_length * sizeof(struct %s*));' % (
            name, self._refname, name, name, self._refname ),
            '  if (msg->%s_data == NULL)' % name,
            '    return (NULL);',
            '  msg->%s_data[msg->%s_length - 1] = %s_new();' % (
            name, name, self._refname),
            '  if (msg->%s_data[msg->%s_length - 1] == NULL) {' % (name, name),
            '    msg->%s_length--; ' % name,
            '    return (NULL);',
            '  }',
            '  msg->%s_set = 1;' % name,
            '  return (msg->%s_data[msg->%s_length - 1]);' % (name, name),
            '}'
            ]
        return code
        
    def CodeComplete(self, structname):
        code = []
        if self.Optional():
            code.append( 'if (%s->%s_set)'  % (structname, self.Name()))

        code.extend(['{',
                     '  int i;',
                     '  for (i = 0; i < %s->%s_length; ++i) {' % (
                structname, self.Name()),
                     '    if (%s_complete(%s->%s_data[i]) == -1)' % (
                self._refname, structname, self.Name()),
                     '      return (-1);',
                     '  }',
                     '}'
                     ])

        return code
    
    def CodeUnmarshal(self, buf, tag_name, var_name):
        code = ['if (%s_%s_add(%s) == NULL)' % (
            self._struct.Name(), self._name, var_name),
                '  return (-1);',
                'if (evtag_unmarshal_%s(%s, %s, '
                '%s->%s_data[%s->%s_length - 1]) == -1) {' % (
            self._refname, buf, tag_name, var_name, self._name,
            var_name, self._name),
                '  %s->%s_length--; ' % (var_name, self._name),
                '  event_warnx("%%s: failed to unmarshal %s", __func__);' % (
            self._name ),
                '  return (-1);',
                '}'
                ]
        return code

    def CodeMarshal(self, buf, tag_name, var_name):
        code = ['{',
                '  int i;',
                '  for (i = 0; i < %s->%s_length; ++i) {' % (
            var_name, self._name),
                '    evtag_marshal_%s(%s, %s, %s->%s_data[i]);' % (
            self._refname, buf, tag_name, var_name, self._name),
                '  }',
                '}'
                ]
        return code

    def CodeClear(self, structname):
        code = [ 'if (%s->%s_set == 1) {' % (structname, self.Name()),
                 '  int i;',
                 '  for (i = 0; i < %s->%s_length; ++i) {' % (
            structname, self.Name()),
                 '    %s_free(%s->%s_data[i]);' % (
            self._refname, structname, self.Name()),
                 '  }',
                 '  free(%s->%s_data);' % (structname, self.Name()),
                 '  %s->%s_data = NULL;' % (structname, self.Name()),
                 '  %s->%s_set = 0;' % (structname, self.Name()),
                 '  %s->%s_length = 0;' % (structname, self.Name()),
                 '}'
                 ]

        return code
        
    def CodeNew(self, name):
        code  = ['%s->%s_data = NULL;' % (name, self._name),
                 '%s->%s_length = 0;' % (name, self._name)]
        code.extend(Entry.CodeNew(self, name))
        return code

    def CodeFree(self, name):
        code  = ['if (%s->%s_data != NULL) {' % (name, self._name),
                 '  int i;',
                 '  for (i = 0; i < %s->%s_length; ++i) {' % (
            name, self._name),
                 '    %s_free(%s->%s_data[i]); ' % (
            self._refname, name, self._name),
                 '    %s->%s_data[i] = NULL;' % (name, self._name),
                 '  }',
                 '  free(%s->%s_data);' % (name, self._name),
                 '  %s->%s_data = NULL;' % (name, self._name),
                 '  %s->%s_length = 0;' % (name, self._name),
                 '}'
                 ]

        return code

    def Declaration(self):
        dcl  = ['struct %s **%s_data;' % (self._refname, self._name),
                'int %s_length;' % self._name]

        return dcl

def NormalizeLine(line):
    global leading
    global trailing
    global white
    global cppcomment
    
    line = cppcomment.sub('', line)
    line = leading.sub('', line)
    line = trailing.sub('', line)
    line = white.sub(' ', line)

    return line

def ProcessOneEntry(newstruct, entry):
    optional = 0
    array = 0
    type = ''
    name = ''
    tag = ''
    tag_set = None
    separator = ''
    fixed_length = ''

    tokens = entry.split(' ')
    while tokens:
        token = tokens[0]
        tokens = tokens[1:]

        if not type:
            if not optional and token == 'optional':
                optional = 1
                continue

            if not array and token == 'array':
                array = 1
                continue

        if not type:
            type = token
            continue

        if not name:
            res = re.match(r'^([^\[\]]+)(\[.*\])?$', token)
            if not res:
                print >>sys.stderr, 'Cannot parse name: \"%s\" around %d' % (
                    entry, line_count)
                sys.exit(1)
            name = res.group(1)
            fixed_length = res.group(2)
            if fixed_length:
                fixed_length = fixed_length[1:-1]
            continue

        if not separator:
            separator = token
            if separator != '=':
                print >>sys.stderr, 'Expected "=" after name \"%s\" got %s' % (
                    name, token)
                sys.exit(1)
            continue

        if not tag_set:
            tag_set = 1
            if not re.match(r'^[0-9]+$', token):
                print >>sys.stderr, 'Expected tag number: \"%s\"' % entry
                sys.exit(1)
            tag = int(token)
            continue

        print >>sys.stderr, 'Cannot parse \"%s\"' % entry
        sys.exit(1)

    if not tag_set:
        print >>sys.stderr, 'Need tag number: \"%s\"' % entry
        sys.exit(1)

    # Create the right entry
    if type == 'bytes':
        if fixed_length:
            newentry = EntryBytes(type, name, tag, fixed_length)
        else:
            newentry = EntryVarBytes(type, name, tag)
    elif type == 'int' and not fixed_length:
        newentry = EntryInt(type, name, tag)
    elif type == 'string' and not fixed_length:
        newentry = EntryString(type, name, tag)
    else:
        res = re.match(r'^struct\[(%s)\]$' % _STRUCT_RE, type, re.IGNORECASE)
        if res:
            # References another struct defined in our file
            newentry = EntryStruct(type, name, tag, res.group(1))
        else:
            print >>sys.stderr, 'Bad type: "%s" in "%s"' % (type, entry)
            sys.exit(1)

    structs = []
        
    if optional:
        newentry.MakeOptional()
    if array:
        newentry.MakeArray()

    newentry.SetStruct(newstruct)
    newentry.SetLineCount(line_count)
    newentry.Verify()

    if array:
        # We need to encapsulate this entry into a struct
        newname = newentry.Name()+ '_array'

        # Now borgify the new entry.
        newentry = EntryArray(newentry)
        newentry.SetStruct(newstruct)
        newentry.SetLineCount(line_count)
        newentry.MakeArray()

    newstruct.AddEntry(newentry)

    return structs

def ProcessStruct(data):
    tokens = data.split(' ')

    # First three tokens are: 'struct' 'name' '{'
    newstruct = Struct(tokens[1])

    inside = ' '.join(tokens[3:-1])

    tokens = inside.split(';')

    structs = []

    for entry in tokens:
        entry = NormalizeLine(entry)
        if not entry:
            continue

        # It's possible that new structs get defined in here
        structs.extend(ProcessOneEntry(newstruct, entry))

    structs.append(newstruct)
    return structs

def GetNextStruct(file):
    global line_count
    global cppdirect

    got_struct = 0

    processed_lines = []

    have_c_comment = 0
    data = ''
    for line in file:
        line_count += 1
        line = line[:-1]

        if not have_c_comment and re.search(r'/\*', line):
            if re.search(r'/\*.*\*/', line):
                line = re.sub(r'/\*.*\*/', '', line)
            else:
                line = re.sub(r'/\*.*$', '', line)
                have_c_comment = 1

        if have_c_comment:
            if not re.search(r'\*/', line):
                continue
            have_c_comment = 0
            line = re.sub(r'^.*\*/', '', line)

        line = NormalizeLine(line)

        if not line:
            continue

        if not got_struct:
            if re.match(r'#include ["<].*[>"]', line):
                cppdirect.append(line)
                continue
            
            if re.match(r'^#(if( |def)|endif)', line):
                cppdirect.append(line)
                continue

            if not re.match(r'^struct %s {$' % _STRUCT_RE,
                            line, re.IGNORECASE):
                print >>sys.stderr, 'Missing struct on line %d: %s' % (
                    line_count, line)
                sys.exit(1)
            else:
                got_struct = 1
                data += line
            continue

        # We are inside the struct
        tokens = line.split('}')
        if len(tokens) == 1:
            data += ' ' + line
            continue

        if len(tokens[1]):
            print >>sys.stderr, 'Trailing garbage after struct on line %d' % (
                line_count )
            sys.exit(1)

        # We found the end of the struct
        data += ' %s}' % tokens[0]
        break

    # Remove any comments, that might be in there
    data = re.sub(r'/\*.*\*/', '', data)
    
    return data
        

def Parse(file):
    """Parses the input file and returns C code and corresponding header
    file."""

    entities = []

    while 1:
        # Just gets the whole struct nicely formatted
        data = GetNextStruct(file)

        if not data:
            break

        entities.extend(ProcessStruct(data))

    return entities

def GuardName(name):
    name = '_'.join(name.split('.'))
    name = '_'.join(name.split('/'))
    guard = '_'+name.upper()+'_'

    return guard

def HeaderPreamble(name):
    guard = GuardName(name)
    pre = (
        '/*\n'
        ' * Automatically generated from %s\n'
        ' */\n\n'
        '#ifndef %s\n'
        '#define %s\n\n' ) % (
        name, guard, guard)
    pre += (
        '#define EVTAG_HAS(msg, member) ((msg)->member##_set == 1)\n'
        '#define EVTAG_ASSIGN(msg, member, args...) '
        '(*(msg)->member##_assign)(msg, ## args)\n'
        '#define EVTAG_GET(msg, member, args...) '
        '(*(msg)->member##_get)(msg, ## args)\n'
        '#define EVTAG_ADD(msg, member) (*(msg)->member##_add)(msg)\n'
        '#define EVTAG_LEN(msg, member) ((msg)->member##_length)\n'
        )

    return pre
     

def HeaderPostamble(name):
    guard = GuardName(name)
    return '#endif  /* %s */' % guard

def BodyPreamble(name):
    global _NAME
    global _VERSION
    
    header_file = '.'.join(name.split('.')[:-1]) + '.gen.h'

    pre = ( '/*\n'
            ' * Automatically generated from %s\n'
            ' * by %s/%s.  DO NOT EDIT THIS FILE.\n'
            ' */\n\n' ) % (name, _NAME, _VERSION)
    pre += ( '#include <sys/types.h>\n'
             '#include <sys/time.h>\n'
             '#include <stdlib.h>\n'
             '#include <string.h>\n'
             '#include <assert.h>\n'
             '#include <event.h>\n\n' )

    for include in cppdirect:
        pre += '%s\n' % include
    
    pre += '\n#include "%s"\n\n' % header_file

    pre += 'void event_err(int eval, const char *fmt, ...);\n'
    pre += 'void event_warn(const char *fmt, ...);\n'
    pre += 'void event_errx(int eval, const char *fmt, ...);\n'
    pre += 'void event_warnx(const char *fmt, ...);\n\n'

    return pre

def main(argv):
    filename = argv[1]

    if filename.split('.')[-1] != 'rpc':
        ext = filename.split('.')[-1]
        print >>sys.stderr, 'Unrecognized file extension: %s' % ext
        sys.exit(1)

    print >>sys.stderr, 'Reading \"%s\"' % filename

    fp = open(filename, 'r')
    entities = Parse(fp)
    fp.close()

    header_file = '.'.join(filename.split('.')[:-1]) + '.gen.h'
    impl_file = '.'.join(filename.split('.')[:-1]) + '.gen.c'

    print >>sys.stderr, '... creating "%s"' % header_file
    header_fp = open(header_file, 'w')
    print >>header_fp, HeaderPreamble(filename)

    # Create forward declarations: allows other structs to reference
    # each other
    for entry in entities:
        entry.PrintForwardDeclaration(header_fp)
    print >>header_fp, ''

    for entry in entities:
        entry.PrintTags(header_fp)
        entry.PrintDeclaration(header_fp)
    print >>header_fp, HeaderPostamble(filename)
    header_fp.close()

    print >>sys.stderr, '... creating "%s"' % impl_file
    impl_fp = open(impl_file, 'w')
    print >>impl_fp, BodyPreamble(filename)
    for entry in entities:
        entry.PrintCode(impl_fp)
    impl_fp.close()

if __name__ == '__main__':
    main(sys.argv)
