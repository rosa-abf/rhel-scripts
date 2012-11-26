#!/usr/bin/python

import subprocess, re, sys, os, logging

from glob import glob

from misc.auxiliary import *
from misc.errors import *

def __generate_changelog(directory, log_prefix, logger):
    re_time = re.compile("^\* (\w{3}), (\d{1,2}) (\w{3}) (\d{4}) (\d{2}:\d{2}:\d{2} [\+\-]\d{4}) (.*)$", re.M)
    re_prefix = re.compile("^\- (%s)(.*)$" % log_prefix )
    cmd = ['git', 'log', '--no-merges', '--simplify-merges',  '--format=* %ad %an <%ae>%n+ Commit: %h%n- %s%n%b', '--date-order', '--date=rfc', '--grep=^%s.*' % log_prefix]

    res = execute_command(cmd, logger, cwd=directory)
    lines = res[0].split('\n')

    line_type = -1
    for i in range(0, len(lines)):
        l = lines[i]
        line_type += 1
        res = re_time.match(l)
        if res:
            (wday, day, month, year, time, other) = res.groups()
            lines[i] = "* %s %s  %s %s %s" % (wday, month, day, year, other)
            line_type = 0
        if line_type == 2:
            res = re_prefix.match(l)
            if not res:
                continue
            lines[i] = "- %s" % res.group(2)
        if line_type > 2:
            lines[i] = '  ' + lines[i]
    return '\n'.join(lines)

def __remove_changelog(spec):
    i = spec.rfind('%changelog')
    if i == -1:
        return spec
    else:
        return spec[:i]

def __add_changelog(spec, changelog):
    out = spec + ("\n%%changelog\n%s\n" % changelog)
    return out

def generate(gitdir, prefix=''):
    '''Get a directory with one spec file and .git subdirectory. Generate changelog from git log and write it to spec file found.
    prefix is a string the log title should start with to go into changelog. This string will be cut out'''

    logging.basicConfig(level=logging.DEBUG)
    logger = logging#.getLogger('libbuild')

    logger.debug("Generating changelog from repository %s" % (gitdir))
    try:
        specglob = os.path.join(gitdir, '*.spec')
        specfile = glob(specglob)[0] #here shoulf be one spec file. Otherwise GitRepository have raised the exception.
        logger.debug("Spec file to write changelog to: " + specfile)

        fd = open(specfile, 'r')
        spec = fd.read()
        fd.close()

        spec_without_changelog = __remove_changelog(spec)
        changelog = __generate_changelog(gitdir, prefix, logger)
        new_spec = __add_changelog(spec_without_changelog, changelog)

        fd = open(specfile, 'w')
        fd.write(new_spec)
        fd.close()
    except Exception, ex:
        logger.exception("Error while generating changelog: %s\n" % str(ex))
        #pass it to client.py
        raise GitException(str(ex))


def main(path):
    generate(path)
    # generate('/Users/avokhmin/workspace/warpc/changelog-test')

# Example:
# python changelog.py /Users/avokhmin/workspace/warpc/changelog-test
if __name__ == '__main__':
    main(sys.argv[1])