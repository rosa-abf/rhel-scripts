#!/usr/bin/env python

#####################################################
#  This module allows running daemon to receive commands
#
# It creates the fifo (configured through main_config.daemon.fifo_path)
#
#
#  USAGE:
#  subclass the ControlReader or ControlWriter class and override 
#  some methods if needed
#
#####################################################

import sys
import os
import threading
import time
import select
import signal
import logging

from common_mtd import *

from auxiliary import *

import daemon

__all__ = ['Control']

class ControlReader(object):
    """ A generic control class.
    Usage: subclass the Control class and override some methods if needed """
    def __init__(self, on_event_func, fifo_path, count=-1):
        ''' If path is none - read cfg.daemon.fifo_path.
        on_event_func - function, will be called on every line read from fifo.'''
        self.logger = logging.getLogger('daemon')

        self.on_event = on_event_func
        self.fifo_path = fifo_path

        if not os.path.exists(self.fifo_path):
            os.mkfifo(self.fifo_path)
        self.logger.info("Starting the ControlReader...")
        self.read_fifo(count)

    @daemon_thread
    def read_fifo(self, count=-1):
        ''' read count lines from fifo. Set count to -1 to unlimited read'''
        cnt = 0
        while True:
            self.fifo_fd = open(self.fifo_path, 'r')
            #r = select.select([self.fifo_fd], [], [])
            res = self.fifo_fd.read()
            if res:
                self.logger.info('Event received: ' + str(res).strip())
                self.parse_event(res)
            else:
                time.sleep(1)
            self.fifo_fd.close()
            cnt += 1
            if cnt == count:
                return

    def parse_event(self, event):
        ''' Parse the string from fifo and call on_event 
        (specified on class initialization) on every line. '''
        lines = event.split('\n')
        for line in lines:
            if not line:
                continue
            self.on_event(line)

class ControlWriter(object):
    """ A generic control class.
    Usage: subclass the Control class and override some methods if needed """

    def __init__(self, fifo_path, need_sudo=False):
        ''' If path is none - read cfg.daemon.fifo_path  
        If need_sudo is True - fifo's owner will be root and noone else will be able to read or write to it'''

        self.fifo_path = fifo_path

        if not os.path.exists(self.fifo_path):
            os.mkfifo(self.fifo_path)

        #protect the fifo file from being affected by another user
        if need_sudo:
            os.chown(self.fifo_path, 0, 0)
            os.chmod(self.fifo_path, 0600)

    def send_message(self, msg):
        ''' Check if the daemon already started and send the message. '''
        d = daemon.Daemon()
        pid = d.get_running_pid()
        if not pid:
            print "Daemon is not working now"
            exit()
        self.write_fifo(msg)

    def write_fifo(self, data):
        ''' Write data to fifo. '''
        self.logger.info('%r' % data)
        self.logger.info('Sending the command "%s" to %s' % (data.strip(), self.fifo_path))
        self.fifo_fd = open(self.fifo_path, 'w')
        self.fifo_fd.write(data)
        self.fifo_fd.flush()
        self.fifo_fd.close()