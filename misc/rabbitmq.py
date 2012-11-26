#!/usr/bin/python
#####################################################
#  Module for working with RabbitMQ
#
#  class MQNode lets server to easily communicate with clients,
#  and to clients easily reply to server.
#  It loads the configuration from server or client config file 
#  (depends on the currently loaded configs)
#  'main.rabbitmq_server_ip' and 'main.rabbitmq_server_port' are used.
#####################################################

import threading
import time
import Queue
import pika
import json
import logging

from pika.adapters import SelectConnection

from errors import *
from auxiliary import *

class MQNode(object):
    ''' Class can send and receive messages from RabbitMQ server. '''
    def __init__(self, options, listen_queue=None, msg_callback=None, exclusive=True,
                get_callback=None, return_callback=None, persistent_table_name=''):
        ''' persistent_table_name - backup the local queue to table with this name '''
        self.logger = logging.getLogger('rabbitmq')

        self.ip = options['rabbitmq_server_ip']
        self.port = int(options['rabbitmq_server_port'])
        self.listen_queue = listen_queue
        self.msg_callback = msg_callback
        self.get_callback = get_callback
        self.return_callback = return_callback
        self.connection = None
        self.channel = None
        self.exclusive = exclusive
        self.send_lock = threading.RLock()
        #self.srs = pika.connection.SimpleReconnectionStrategy()
        self.logger.debug('Starting the RabbitMQ thread...')

        self.persistent_table_name = persistent_table_name

        if self.persistent_table_name:
            db = __import__('misc').db
            self.queue = db.DB_Queue(self.persistent_table_name,
                                     options['mq_host'], options['mq_port'], options['mq_database'],
                                     options['mq_user'], options['mq_password'], options['mq_max_connections'])
        else:
            self.queue = Queue.Queue() 

        self._loop()

    @daemon_thread
    def _loop(self):
        '''Serve consuming delivering messages. '''
        while True:
            self.logger.debug('in loop...')
            try:
                self.connection = SelectConnection(pika.ConnectionParameters(
                    host=self.ip, port=self.port), self.on_connected)
                self.connection.add_timeout(1, self.publish_messages)
                self.connection.ioloop.start()
            except Exception, ex:
                pass
            time.sleep(10)
            self.logger.info('Trying to reconnect to RabbitMQ server %s:%s...' % (self.ip, self.port))

    def __del__(self):
        self.connection.close()
        self.logger.info('The connection to RabbitMQ server %s:%d have been closed' % (self.ip, self.port))

    def on_connected(self, connection):
        """Called when we are fully connected to RabbitMQ"""
        # Open a channel
        try:
            self.connection = connection
            self.connection.channel(self.on_channel_open)
        except Exception, ex:
            self.logger.exception("Error while connecting")

    def on_channel_open(self, new_channel):
        """Called when our channel has opened"""

        try:
            self.channel = new_channel
            self.channel.add_on_close_callback(self.on_close_callback)
            self.channel.add_on_return_callback(self.on_return_callback)
            if self.listen_queue:
                self.channel.queue_declare(queue=self.listen_queue, durable=True, exclusive=self.exclusive, auto_delete=False, callback=self.on_queue_declared)
        except Exception, ex:
            self.logger.exception("Error while opening a channel")

    def on_close_callback(self, p1, p2):
        ''' This method will be called on closing the pika channel '''
        self.logger.error("Channel have been closed. Code: %s; Text: %s" %(str(p1), p2))

    def on_return_callback(self, method, header, body):
        ''' This methos will be called when the message was not sent by rabbitmq server and was returned.
        It can happen if no query exists (method.reply_code=312)'''
        try:
            if self.return_callback:
                data = json.loads(body)
                self.return_callback(method, header, data)
                self.channel.add_on_return_callback(self.on_return_callback)
        except Exception, ex:
            self.logger.exception('Returned message processing failed.')

    def on_queue_declared(self, frame):
        """Called when RabbitMQ has told us our Queue has been declared, 
        frame is the response from RabbitMQ."""

        try:
            if self.listen_queue:
                self.channel.basic_qos(prefetch_count=1)
                self.channel.basic_consume(self.handle_delivery, queue=self.listen_queue)
        except Exception, ex:
            self.logger.exception("Error while declaring a query")

    def handle_delivery(self, channel, method, header, body):
        """Called when we receive a message from RabbitMQ
         All the data being sent as string (serialized objects). 
        Deserialize it and call the real callback with the deserialized data"""

        try:
            print body
            data = json.loads(body)
            self.logger.debug('Received message: %s %s' % (data['ID'], data['mtype']))
        except Exception, ex:
            self.logger.exception("Error while deserializing received data")

        try:
            if self.msg_callback:
                self.msg_callback(channel, method, header, data)
        except:
            self.logger.exception('Exception catched on illegal level!')

    def publish_messages(self):
        ''' Publish messages from the local queue to RabbitMQ server.
        This method is called once in a second from pika thread.'''
        try:
            while not self.queue.empty():
                self.send_lock.acquire()
                if self.persistent_table_name:
                    self.ID, self.current_item = self.queue.get()
                else:
                    self.current_item = self.queue.get()
                self.current_item['properties'] = pika.BasicProperties(**self.current_item['properties'])
                self.channel.basic_publish(**self.current_item)
                if self.persistent_table_name:
                    self.queue.rem(self.ID)
                self.send_lock.release()
            self.connection.add_timeout(1, self.publish_messages)
        except Exception, ex:
            self.logger.exception("Error while sending messages.")
            #return unprocessed item back to queue
            if not self.persistent_table_name:
                self.queue.put(self.current_item)

    def send(self, data, queue, immediate=False):
        ''' Take a json-capable data, place it to the local queue 
        and send when it's possible. '''

        s = json.dumps(data)

        self.logger.debug('Adding the request to queue %s: %s %s' % (queue, data['ID'], data['mtype']))

        self.queue.put(dict(
                exchange='',
                routing_key=queue,
                body=s,
                mandatory=True,
                immediate=immediate,
                properties=dict(
                    delivery_mode = 2, # make message persistent
                )))

    def _get_callback(self, ch, method, properties, body):
        ''' Private callback for basic_get method. 
        It will call get_callback (passed while class initialization) if defined.'''
        try:
            data = json.loads(body)

            self.logger.debug('Message pulled from client queue: %s %s' % (data['ID'], data['mtype']))
            if self.get_callback:
                self.get_callback(ch, method, properties, data)
        except:
            self.logger.exception('Error while pulling message from queue')

    def get(self, queue):
        ''' Get one message from 'queue' '''
        if not self.channel:
            return
        res = self.channel.basic_get(self._get_callback, queue=queue, no_ack=True)
