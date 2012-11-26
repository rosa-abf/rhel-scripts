#!/usr/bin/python

#####################################################
#  This module works with git.
#  It can clone repository, checkout to the commit or branch.
#  WARNING: on creation of GitRepository object, keep this object
#  while you need the data in the temporary directory.
#  When the object removed - temp directory is removed.
#
#  In case of internal errors GitException will be raised.
#
#  USAGE:
#  Write something like that:
#  daemon = RepoManageDaemon('repo_manage.pid', 'stdoutb_repo', 'stderrb_repo')
#  #these options are not in config file, because you can start more than one copy of your program
#
#  Now call daemon.start(), daemon.stop() or daemon.restart()
#
#####################################################


import os, sys
import shutil
import tempfile
import subprocess
import logging

from auxiliary import *
from errors import *

class GitRepository(object):
    '''initialize this class with the git url and commit hash.
    Repository will be cloned into the temporary directory and checked out
    to the commit cpecified. 
    WARNING: on creation of GitRepository object, keep this object
    while you need the data in the temporary directory.
    When the object removed - temp directory is removed too.'''

    def __init__(self, git_url, commit_hash):
        self.logger = logging.getLogger('git')

        self.url = git_url
        self.commit_hash = commit_hash

        self.mktempdir()
        self.clone()

    def __del__(self):
        try:
            if os.path.exists(self.temp_dir):
                shutil.rmtree(self.temp_dir)
                self.logger.debug('Git directory %s have been removed' % self.temp_dir)
        except Exception, ex:
            self.logger.warning("Could not remove directory %s: %s" % (self.temp_dir, str(ex)))

    def clone(self):
        ''' Clone the remote git repository and check the commit out '''
        old_dir = os.getcwd()
        os.chdir(self.temp_dir)
        try:
            execute_command(['git','clone', self.url, self.temp_dir], self.logger)
            res = execute_command(['git','checkout', self.commit_hash], self.logger)
        except Exception, ex:
            raise GitException(str(ex))
        finally:
            os.chdir(old_dir)

    def mktempdir(self):
        bn = os.path.basename(self.url)
        self.temp_dir = tempfile.mkdtemp(prefix='%s-' % (bn))
        os.chmod(self.temp_dir, 0777)
        self.logger.debug('Temporary git directory created: ' + self.temp_dir)