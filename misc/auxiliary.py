import subprocess, os, sys
import threading
import traceback

def execute_command(command, log, cwd=None):
    '''Execute command using subprocess.Popen and return its stdout and stderr output string. 
    If return code is not 0, log error message and raise error'''
    log.debug("Executing command: " + str(command))
    res = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd)
    output = list(res.communicate())

    if(res.returncode != 0):
        log.error("Error while calling command. \nStdout: %s\nStderr: %s" % (output[0], output[1]))
        raise Exception("Error while calling command " + str(command))

    return (output[0], output[1]) 

def mkdirs(path):
    ''' the equivalent of mkdir -p path'''
    if os.path.exists(path):
        return
    path = os.path.normpath(path)
    items = path.split('/')
    p = ''
    for item in items:
        p += '/' + item
        if not os.path.isdir(p):
            os.mkdir(p)

def daemon_thread(foo):
    '''This decorator lets you to make every function call 
            to create another daemon thread'''
    def daemon_runner(*args, **kwargs):
        worker_thread = threading.Thread(target=foo, args=args, kwargs=kwargs)
        worker_thread.daemon = True
        worker_thread.start()
    return daemon_runner

def get_exc_source():
    '''Call it when an exception raised. 
    It will return dictionary {'filename':'...', 'method':'...'}'''

    res = traceback.extract_tb(sys.exc_info()[2])
    print dict(filename= os.path.basename(res[-1][0]), method=res[-1][2])
    
def method_in_trace(method_name):
    '''Check if the method_name specified is among the list of functions in the traceback'''
    res = traceback.extract_tb(sys.exc_info()[2])
    for item in res:
        if item[2] == method_name:
            return True
    return False

def file_in_trace(file_name):
    '''Check if the file_name specified is among the list of files in the traceback.
    file_name should not contain path, base name only'''
    res = traceback.extract_tb(sys.exc_info()[2])
    for item in res:
        if os.path.basename(item[0]) == file_name:
            return True
    return False

def reraise_with_traceback(exc=None):
    '''In 'except' section call this function to raise the original 
    exception with the original traceback.
    exc - exception to raise. If None - raise the exception thrown'''
    ei = sys.exc_info()
    if exc:
        exc = ei[0]
    raise exc, ei[1], ei[2]