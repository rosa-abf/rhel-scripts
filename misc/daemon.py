#!/usr/bin/env python

#####################################################
#  This module helps you to demonize your process. 
#
#  USAGE:
#  Write something like that:
#  daemon = RepoManageDaemon()
#
#  Now call daemon.start(), daemon.stop() or daemon.restart()
# 
#####################################################

import sys
import os
import time
import atexit
import shutil
import subprocess
import logging

from common_mtd import *

from signal import SIGTERM

__all__ = ['Daemon']

class Unbuffered:
    ''' Class can make descriptor write process unbuffered.
    Usage: sys.stdout=Unbuffered(sys.stdout)'''
    def __init__(self, stream):
        self.stream = stream
    def write(self, data):
        self.stream.write(data)
        self.stream.flush()
    def __getattr__(self, attr):
        return getattr(self.stream, attr)

class Daemon(object):
    """ A generic daemon class.
    Usage: subclass the Daemon class and override the run() method """
    def __init__(self, pidfile, stdin='/dev/null', stdout='/dev/null', stderr='/dev/null', need_sudo=False):
        ''' If need_sudo is True - check sudo rights and exit if needed. '''

        self.logger = logging.getLogger('daemon')

        if need_sudo and os.getuid() != 0:
            print "You need sudo rights."

            exit()

        self.soft_restart = False
        self.need_sudo = need_sudo

        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
        self.pidfile = pidfile

    def get_running_pid(self):
        ''' Get the pid of the already running daemon (if present), or return None '''
        try:
            pf = file(self.pidfile,'r')
            pid = int(pf.read().strip())
            pf.close()
        except Exception, ex:
            pid = None
        return pid

    def daemonize(self):
        """ do the UNIX double-fork magic, see Stevens' "Advanced
        Programming in the UNIX Environment" for details (ISBN 0201563177)
        http://www.erlenstar.demon.co.uk/unix/faq_2.html#SEC16 """
        try:
            pid = os.fork()
            if pid > 0:
                # exit first parent
                sys.exit(0)
        except OSError, e:
            message = "Fork #1 failed: %d (%s)\n" % (e.errno, e.strerror)
            self.logger.error(message)
            print message

            sys.exit(1)

        # decouple from parent environment
        #os.chdir("/")
        os.setsid()
        os.umask(0)

        # do second fork
        try:
            pid = os.fork()
            if pid > 0:
                # exit from second parent
                sys.exit(0)
        except OSError, e:
            message = "Fork #2 failed: %d (%s)\n" % (e.errno, e.strerror)
            self.logger.error(message)
            print message
            sys.exit(1)

        self.manage_files()

    def manage_files(self):
        ''' Redirect standard file descriptors '''
        sys.stdout.flush()
        sys.stderr.flush()
        self.si = file(self.stdin, 'r')
        self.so = file(self.stdout, 'a+')
        self.se = file(self.stderr, 'a+', 0)
        os.dup2(self.si.fileno(), sys.stdin.fileno())
        os.dup2(self.so.fileno(), sys.stdout.fileno())
        os.dup2(self.se.fileno(), sys.stderr.fileno())

        if not isinstance(sys.stdout, Unbuffered):
            sys.stdout=Unbuffered(sys.stdout)
            sys.stderr=Unbuffered(sys.stderr)                 
        # write pidfile
        atexit.register(self.delpid)
        if not self.soft_restart:
            pid = str(os.getpid())
            file(self.pidfile,'w+').write("%s\n" % pid)
        self.soft_restart = False

    def delpid(self):
        ''' Remove pid file. This method will be called on exit (via atexit module) '''
        if not self.soft_restart:
            os.remove(self.pidfile)

    def start(self):
        """ Start the daemon """
        if self.soft_restart:
            self.logger.info("Soft restart: " + str((sys.argv[0], 'start')))
            os.execl(sys.executable, sys.executable, sys.argv[0], 'start')
            self.manage_files()
        else:
            self.logger.info("Starting a daemon...")
            # Check for a pidfile to see if the daemon already started
            pid = self.get_running_pid()

            if pid and not self.soft_restart:
                message = "Pidfile %s already exist. Daemon already running?" % self.pidfile
                print(message)
                pid = None
                sys.exit(1)

            # Start the daemon
            self.daemonize()
        self.run()

    def stop(self):
        """ Stop the daemon """

        if self.soft_restart:
            self.logger.info("Softly stopping a daemon...")
            os.remove(self.pidfile)
            return

        # Get the pid from the pidfile
        self.logger.info("Stopping a daemon...")
        pid = self.get_running_pid()

        if not pid:
            message = "Pidfile %s does not exist. Daemon not running?" % self.pidfile
            self.logger.error(message)
            return # It's not a critical error while restarting

        # Try killing the daemon process
        self.logger.info('Killing the process %d' % pid)
        try:
            while 1:
                os.kill(pid, SIGTERM)
                time.sleep(0.1)
        except OSError, err:
            err = str(err)
            if err.find("No such process") > 0:
                if os.path.exists(self.pidfile):
                    os.remove(self.pidfile)
            else:
                self.logger.exception('Error while killing process')
                sys.exit(1)

    def restart(self, force=True):
        """ Restart the daemon. """
        self.soft_restart = not force
        self.stop()
        self.start()

    def run(self):
        """ You should override this method when you subclass Daemon. It will be called after the process has been
        daemonized by start() or restart()."""