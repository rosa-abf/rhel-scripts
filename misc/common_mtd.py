#/usr/bin/python -t
#coding:UTF-8

import sys
import os

import logging

from auxiliary import *

HaveToRestart = False
HaveToStop = False

def abs_pth(fl, conf):
    return os.path.realpath('/'.join(fl.split('/')[:-1] + [conf]))

class Units:
    thr_s = []
    def __init__(self, unit=None):
        self.t_out = 65
        self.unit = unit
        self.to_thr()
        print '%s done' % unit

    def to_thr(self):
        if not self.unit:
            print 'Not set name of unit.'
            return
        from threading import Thread
        cnt = 6
        while cnt:
            print 6-cnt
            #self.cycl()
            self.thr = Thread(target=self.cycl, name='%s thr #%d' % (self.unit, cnt))
            self.thr.start()
            cnt -=1
        print '\narray_in_process'

    @daemon_thread
    def cycl(self):
        import threading
        from time import sleep
        th_n = '%s done' % threading.currentThread().getName()
        Units.thr_s.append(th_n)
        #if len(Units.thr_s) > 3:
        #    Units.thr_s.insert(len(Units.thr_s)-3,th_n)
        #    Units.thr_s.pop(len(Units.thr_s)-1)
        sleep(self.t_out)
        print '%s\n' % th_n
        
def on_msg(msg):
    ''' It will be called when control message received (from fifo)
    '''

    logger = logging.getLogger('daemon')

    global HaveToStop, HaveToRestart

    items = msg.split()

    if items[0] == 'stop':
        HaveToStop = True

    if items[0] == 'restart':
        HaveToStop = True
        HaveToRestart = True

    logger.info("Command to %s received..." % items[0])

def parse_command_line(tip):
    ''' Parse command line, adjust some flags and warn in some cases
    '''
    global command_line
    import argparse
    tip = os.path.basename(tip).split('_d')[0]
    tips = 'Building '
    if tip == 'repoman':
        tips = tip.capitalize()
    else:
        tips += tip
    parser = argparse.ArgumentParser(description='%s for ABF' % tips) 
    parser.add_argument('action', action='store', choices=['start', 'stop', 'stop-soft', 'restart', 'restart-soft', 'message'], help="The main action to do")
    tip2 = tip
    if not tip == 'client':
        tip2 = 'server'
    else:
        parser.add_argument('-u', '--uuid', help='Client uuid')
    parser.add_argument('-m', '--msg', help='Message to send to %s' % tip2)
    command_line  = parser.parse_args(sys.argv[1:])
    if command_line.action == 'message' and not command_line.msg:
        print "No --msg option found"
        exit()
    return command_line, tip

def dmnz(cnt):
    try:
        pid = os.fork()
        if pid > 0:
            # exit parent
            sys.exit(0)
    except OSError, e:
        message = "Fork %d failed: %d (%s)\n" % (cnt, e.errno, e.strerror)
        logger = logging.getLogger('daemon')
        logger.error(message)
        sys.exit(1)
