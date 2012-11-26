class ProcessedException(Exception):
    ''' If you've catched and handled the exception and have to raise the exception 
    to pass it upward - use this exception. '''
    pass

class BuildingException(Exception):
    pass

class IncorrectMtypeError(Exception):
    pass

class MalformedMessageError(Exception):
    pass

class AlreadyExistsError(Exception):
    pass

class DoesNotExistError(Exception):
    pass

class MockException(BuildingException):
    pass    

class GitException(Exception):
    pass   

class DBConnectionClosedException(Exception):
    pass 

class DBIncorrectQueryException(Exception):
    pass

class DBIconsistentException(Exception):
    ''' When some problems with DB structure found - throw this exception '''
    pass

class RabbitmqConnectionClosed(Exception):
    pass

class InternalError(Exception):
    pass