#!/usr/bin/python -t
# -*- coding: UTF-8 -*-

#################################################
#      Manipulate database pool connections 
#              and execute queries.
#
# DESCRIPTION:
#  This module lets you to create database connection and execute sql 
#  queries in a thread-safe way.
#
# USAGE:
#  # pass any object that has fields: user, password, database, host and max_connections.
#  # Create the connection pool and a virtual connection:
#  conn = DB_Pool().get_connection()
#  # Now you can execute queries:
#  conn.execute('select * from arch;')
#  # Close connection when it is not needed anymore:
#  conn.close()
#
# TODO:
# * Fail-safe: lost connection to database
#################################################

import threading
import json
import sys
import Queue
import logging
import psycopg2
import psycopg2.extras
import psycopg2.extensions
#import re

from DBUtils.PooledDB import PooledDB
from errors import *
from common_mtd import *

def escape_string(s):
    #return psycopg2.extensions.QuotedString(s).getquoted()
    return s.replace("'", "''")

#TODO complete the ability to connect to different databases
# > pg_bouncer <

class DB_Pool(object):
    #'''Manages a pool of virtual connections to database.
    #This class is a singleton.'''
    #_instance = None
    #def __new__(cls, *args, **kwargs):
    #    if not cls._instance:
    #        cls._instance = super(DB_Pool, cls).__new__(
    #                            cls, *args, **kwargs)
    #    return cls._instance

    @classmethod
    def close(cls):
        ''' Before exiting the program, do not forget to call DB_Pool.close().
        It will close the pool if it is opened. '''
        """
        if cls._instance.pool:
            self.logger.debug("Closing connection pool")
            cls._instance.pool.close()
        """
        pass

    def __init__(self, host, port, database, user, password, max_connections):
        self.logger = logging.getLogger('db')

        try:
            #if 'pool' in self.__dict__:
            #    return # do not reinitialize the pool

            self.pool = PooledDB(psycopg2, int(max_connections), user = user,
                password = password, host = host, port = port, database = database)

            self.logger.debug('Connection pool to %s/%s have been created.' % (host, database))
        except Exception as e:
            self.logger.exception('Could not connect to database %s/%s with user %s' % (host, database, user))
            raise

    def get_connection(self):
        return DB_Connection(self.pool)

class DB_Connection(object):
    '''Represents a virtual connection, operating some real connection.
    Lets you to execute queries.'''
    def __init__(self, pool):
        self.logger = logging.getLogger('db')

        self.pool = pool
        self.rlock = threading.RLock()
        try:
            self.conn = self.pool.connection()
            self.cursor = self.conn.cursor(cursor_factory = psycopg2.extras.RealDictCursor)
        except Exception as e:
            self.logger.exception('Could not connect to database %s/%s with user %s' % 
                                        (host, database, user)) # TODO
            raise e
                                        
    def __del__(self):
        self.close()

    def close(self):
        self.rlock.acquire()
        #self.logger.debug('Closing the connection to databse')
        if self.cursor:
            self.cursor.close()
            self.cursor = None
        if self.conn:
            self.conn.close()
            self.conn = None
        self.rlock.release()
    
    #def fetchAllAssoc(self):
    #    if not self.cursor: 
    #        return None
    #    rows = self.cursor.fetchall()
    #    if rows is None: 
    #        return None
    #    cols = [desc[0] for desc in self.cursor.description]
    #    res = []
    #    for row in rows:
    #        res.append(dict(zip(cols, row)))
    #    return res

    def execute(self, command, assoc = True, nolog=False):
        ''' Execute the sql query and return the result as a dictionary.
        If nolog is True - no debug messages will be placed to log'''
        if not nolog:
            self.logger.debug('Executing command ' + command)
        if not self.cursor:
            self.logger.error('Trying to execute query on closed cursor.')
            raise DBConnectionClosedException('Cursor closed')
        
        self.rlock.acquire()

        try:
            self.cursor.execute(command)
            #self.conn.commit()
            self.logger.debug(command)
        except Exception, ex:
            #self.conn.rollback()
            self.logger.error(command)
            self.logger.error('Could not execute sql query ' + str(ex))
            self.rlock.release()
            raise DBIncorrectQueryException, str(ex), sys.exc_info()[2]

        try:
            if self.cursor.description:
                #if assoc:
                #    res = self.fetchAllAssoc()
                #else:
                #    res = self.cursor.fetchall()
                #    if not nolog:
                #        self.logger.debug('Columns: ' + str(self.cursor.description))
                res = self.cursor.fetchall()
                desc = 'Records'

                if not nolog:
                    self.logger.debug('Columns: ' + str(self.cursor.description))
            else:
                res = self.cursor.rowcount
                desc = 'Result'
        except Exception, ex:
            self.logger.exception('Error while fetching query results.')
            raise DBIncorrectQueryException(str(ex))
        finally:
            self.rlock.release()

        if not nolog:
            self.logger.debug(desc + ': ' + str(res))

        return res

    def commit(self):
        self.conn.commit()

    def rollback(self):
        self.conn.rollback()

#################################################
# Dictionary-like class, that keeps all the data in the database.
#
# USAGE:
#  #table 'table_name' will be used to store data in
#  d = DB_Dict('table_name') 
#  d['key1'] = 'val1' # insert table row
#  d['key1'] = {'a':1, 'b':['c', 2]} # update table row
#  print d['key1'] # do not read from database 
#                #(from local dictionary only)
#  print d.pop('key1') # remove table row
#  d = None #remove object and close its DB connection.
#
# NOTES:
#  * Key can be only of type string, but value - any 
#    appropriate for json serializing type.
#################################################

class DB_Dict(dict):
    ''' Dictionary-like class, that keeps all the data in the database. '''
    def __init__(self, table_name, host, port, database, user, password, max_connections):
        super(DB_Dict, self).__init__()

        self.logger = logging.getLogger('db')

        self.table_name = table_name
        self.conn = DB_Pool(host, port, database, user, password, max_connections).get_connection()
        self.load()

    def load(self):
        ''' [re]load the contents of local buffer from the database '''
        self.logger.debug('Loading the DB_Dict from ' + self.table_name)

        #self.conn.execute('create table if not exists %s (key text, value text, primary key(key));' 
        #                                      % self.table_name, nolog=True)
        res = self.conn.execute("select relname, pg_class.relkind as relkind FROM pg_class, pg_namespace \
                                 where (pg_class.relnamespace = pg_namespace.oid) and \
                                 (pg_class.relkind IN ('v', 'r')) and \
                                 (pg_namespace.nspname = 'public') and \
                                 (relname = '%s')" % self.table_name, nolog = True)

        if not res:
            self.conn.execute("create table %s (key text, value text, primary key(key))" % self.table_name, nolog = True)             

        self.conn.commit()

        res = self.conn.execute('select * from %s' % self.table_name, nolog=True)

        for item in res:
            key = item['key']
            val = item['value']
            val = json.loads(val)
            super(DB_Dict, self).__setitem__(key, val)

        self.logger.debug('Items loaded: ' + str(len(self)))

    def __setitem__(self, key, value):
        ''' Save the data to a database '''
        if key in self and self[key] == value:
            return

        val = escape_string(json.dumps(value))
        #val = re.escape(json.dumps(value))

        if not key in self:
            self.conn.execute("insert into %s values ('%s', '%s');" % 
                    (self.table_name, key, val), nolog=True)
        else:
            self.conn.execute("update %s set value='%s' where key='%s';" % 
                    (self.table_name, val, key), nolog=True)

        self.conn.commit()

        super(DB_Dict, self).__setitem__(key, value)

    def pop(self, key, init=None):
        ''' Remove the item from a database (and local buffer) and return it '''
        if init is not None and key not in self:
            return init

        val = super(DB_Dict, self).pop(key, init)

        if not val:
            raise KeyError('Key %s does not exist' % key)

        self.conn.execute("delete from %s where key='%s'" % (self.table_name, key), nolog=True)

        self.conn.commit()

        return val

# Common usage:
# d = DB_Dict2('table_name', ['key1', 'key2'])
# d['some_string1'] = {'key1':'val1', 'key2':'val2'}
# d['some_string2'] = {'key1':'val3', 'key2':'val4'}
# print d.pop('some_string')
# d = None
# d = DB_Dict2('table_name', ['key1', 'key2'])
# print d

class DB_Dict2(dict):
    '''Creates a dictionary-like interface to communicate with DB. 
    Structure: {<id>: {keys:values}}
    A list of keys will be passed to constructor.
    Each value can be of any json-serializable data (string, dictionary, list, number...)
    '''
    class DB_Row(dict):
        def __init__(self, dbdict, params, loading=False):
            super(DB_Dict2.DB_Row, self).__init__()

            self.logger = logging.getLogger('db')

            self.table_name = dbdict.table_name
            self.fields = dbdict.fields
            self.ID = params[self.fields[0]]
            self.conn = dbdict.conn
            
            self._set_self(params)

            if not loading:
                self._add_to_db(params)

        def _add_to_db(self, params):
            t = "'"

            for item in self.fields:
                if item == 'id':
                    t += params[item] + "', '"
                else:
                    t += escape_string(json.dumps(params[item])) + "', '"
                    #t += re.escape(json.dumps(params[item])) + "', '"

            t = t[:-3]

            print t

            self.conn.execute("insert into %s values (%s);" % 
                    (self.table_name, t))

            self.conn.commit()

        def _set_self(self, params):
            for key in self.fields[1:]:
                if key not in params:
                    raise KeyError('Not all the necessary keys present in params passed to constructor. Missing key:' + key)

                super(DB_Dict2.DB_Row, self).__setitem__(key, params[key])

        def __setitem__(self, key, value):
            ''' Save the data to a database '''
            if key not in self.fields[1:]:
                raise KeyError('Key "%s" does not exist' % key)

            data = escape_string(json.dumps(value))
            #data = re.escape(json.dumps(value))

            self.conn.execute("update %s set %s='%s' where %s='%s';" % 
                    (self.table_name, key, data, self.fields[0], self.ID))

            self.conn.commit()

            super(DB_Dict2.DB_Row, self).__setitem__(key, value)

        def pop(self, key, init=None):
            raise Exception('Not permitted')  

    def __init__(self, table_name, fields, host, port, database, user, password, max_connections):
        '''table_name - the name of table to store data to.
        fields - a list of columns in database table'''
        super(DB_Dict2, self).__init__()

        self.logger = logging.getLogger('db')

        self.table_name = table_name
        self.fields = ['id'] + fields
        self.conn = DB_Pool(host, port, database, user, password, max_connections).get_connection()
        self.load()

    def __setitem__(self, key, params):
        ''' Save the data to a database '''
        p = params.copy()

        p[self.fields[0]] = key

        if not key in self:
            super(DB_Dict2, self).__setitem__(key, 
                    DB_Dict2.DB_Row(self, p))
        else:
            self[key].update(p)

    def load(self):
        self.t = ''

        for item in self.fields:
            self.t += item + ' text, '

        #self.conn.execute('create table if not exists %s (%sprimary key(%s));' 
        #                     % (self.table_name, self.t, self.fields[0]), nolog=True)
        res = self.conn.execute("select relname, pg_class.relkind as relkind FROM pg_class, pg_namespace \
                                 where (pg_class.relnamespace = pg_namespace.oid) and \
                                 (pg_class.relkind IN ('v', 'r')) and \
                                 (pg_namespace.nspname = 'public') and \
                                 (relname = '%s')" % self.table_name, nolog = True)

        if not res:
            self.conn.execute('create table %s (%sprimary key(%s))' % (self.table_name, self.t, self.fields[0]), nolog=True)

        self.conn.commit()

        res = self.conn.execute('select * from %s' % self.table_name, nolog=True)

        ID_name = self.fields[0]

        for item in res:
            params = {}

            for field in item:
                if field == self.fields[0]:
                    text = item[field]
                else:
                    text = json.loads(item[field])
                params[field] = text

            super(DB_Dict2, self).__setitem__(item[ID_name],
                    DB_Dict2.DB_Row(self, params, loading=True))

    def pop(self, key, init=None):
        ''' Remove the item from a database (and local buffer) and return it '''
        if init is not None and key not in self:
            return init

        val = super(DB_Dict2, self).pop(key, init)

        if not val:
            raise KeyError('Key %s does not exist' % key)

        self.conn.execute("delete from %s where %s='%s'" % (self.table_name, self.fields[0], key), nolog=True)

        return val
                                
# Common usage:
# q = DB_Queue('table_name_queue')
# q.put('some data') # it will be stored in DB
# q = None
# q = DB_Queue('table_name_queue') # item will be loaded
# ID, res = q.get()
# # process the data
# q.rem(ID)

class DB_Queue():
    ''' Special queue that keeps all the data in the database. 
    Do not forget to call rem(data) to remove the item from DB, but do 
    it after get and after processing the data extracted. '''
    def __init__(self, table_name, host, port, database, user, password, max_connections):
        #super(DB_Queue, self).__init__()
        self.logger = logging.getLogger('db')

        self.table_name = table_name
        self.conn = DB_Pool(host, port, database, user, password, max_connections).get_connection()
        self.queue = Queue.Queue()
        self.load()

    def load(self):
        ''' [re]load the contents of local buffer from the database '''
        self.logger.debug('Loading the DB_Queue from ' + self.table_name)

        #self.conn.execute('create table if not exists %s (id SERIAL, data text, PRIMARY KEY(id));' 
        #                                      % self.table_name, nolog=True)
        res = self.conn.execute("select relname, pg_class.relkind as relkind FROM pg_class, pg_namespace \
                                 where (pg_class.relnamespace = pg_namespace.oid) and \
                                 (pg_class.relkind IN ('v', 'r')) and \
                                 (pg_namespace.nspname = 'public') and \
                                 (relname = '%s')" % self.table_name, nolog = True)

        if not res:
            self.conn.execute('create table %s (id SERIAL, data text, PRIMARY KEY(id))' % self.table_name, nolog=True)

        self.conn.commit()

        res = self.conn.execute('select * from %s' % self.table_name, nolog=True)

        for item in res:
            ID = item['id']
            data = item['data']
            d = json.loads(data)
            self.queue.put((ID, d))
            self.logger.debug('Item loaded: ' + str(d))

    def put(self, data):
        d = escape_string(json.dumps(data))
        #d = re.escape(json.dumps(data))

        res = self.conn.execute("insert into %s (data) values ('%s') returning id;" % 
                    (self.table_name, d), nolog=True)

        self.conn.commit()

        ID = res[0]['id']

        self.queue.put((ID, data))

    def get(self):
        return self.queue.get()

    def rem(self, ID):
        self.conn.execute("delete from %s where id=%s;" % 
                    (self.table_name, ID), nolog=True)

        self.conn.commit()

    def empty(self):
        return self.queue.empty()

"""
def main():
    host
    port
    database
    user
    password
    max_connections

    d = DB_Dict2('table_name_2', ['state', 'platform', 'arch'])
    print d
    d['asdgdfh'] = {'state':'a2', 'platform':'pl', 'arch':'arch'}
    #d['asdgdfh']['arch'] = 'arch2'
    exit()

    d = DB_Dict('table_name', host, port, database, user, password, max_connections)
    print d
    d['key1'] = {'val1':'aaa', 'val2':'bbb'}
    d['key1']['val2'] = 'eee'
    d['key1'] = d['key1'].copy()
    print d['key1']

    #print d.pop('key1')
    d = None
    DB_Pool.close()
    exit()

    conn = DB_Pool(host, port, database, user, password, max_connections).get_connection()
    print conn.execute('select * from arch;')
    conn.close()
    DB_Pool.close()

if __name__ == '__main__':
    main()
"""