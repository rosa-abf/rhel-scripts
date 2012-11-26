#!/usr/bin/env python
#-*- coding: utf-8 -*-
"""
Python module to generate build lists
"""
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4

import sys
#import psycopg2
#import psycopg2.extras

from db import DB_Pool

sql_quieries = {
  "srpm_reverse":
    """
    select pr.name as project_name, s.name as srpm_name, s.version as srpm_version from pkg_src_require sr
    inner join pkg_src s on (sr.idpkg_src = s.idpkg_src)
    inner join project pr on (pr.idproject=s.idproject)
    inner join repository rp on (rp.idrepository=pr.idrepository)
    inner join platform pl on (pl.idplatform = rp.idplatform)
    where pl.idplatform = %s and
          sr.name = '%s' and
          rp.frombuild = 0 and
          s.idbuild_platform %s
    """,
  "srpm_not_reverse_inner_join":
     """
     select sr.name, pl.idplatform from platform pl
     inner join repository rp on (rp.idplatform = pl.idplatform) and (rp.frombuild = 0)
     inner join projects pr on (pr.idrepository = rp.idrepository)
     inner join projects prv on (prv.idrepository = rp.idrepository)
     inner join srpms s on (s.idprojects = pr.idprojects) and
                           (s.idbuild_platform %s) and
                           (s.name = '%s')
     inner join srpm_requirename sr on (sr.idsrpms = s.idsrpms)
     where (pl.idplatform = %s)
     """,
  "srpm_not_reverse":
     """
     select prv.name as project_name, sv.name as srpm_name, sv.version as srpm_version from platform pl
     inner join (%s) as deps on (deps.idplatform = pl.idplatform)
     inner join repository rp on (rp.idplatform = pl.idplatform) and (rp.frombuild = 0)
     inner join projects prv on (prv.idrepository = rp.idrepository)
     inner join srpms sv on (sv.idprojects = prv.idprojects) and
                            (sv.idbuild_platform %s) and
                            (sv.name = deps.name)
     """,
   "project_info":
     """
     select s.name, s.version from platform pl 
     inner join repository rp on (rp.idplatform = pl.idplatform) and (rp.frombuild = 0)
     inner join projects pr on (pr.idrepository = rp.idrepository) and (pr.name = '%s')
     inner join srpms s on (s.idprojects = pr.idprojects) and 
                           (s.idbuild_platform %s)
     where (pl.idplatform = %s)
     """
}
    

class BuilList(object):
    def __init__(self, project_name = None, project_version = None, plname = None, arch = None, bplname = None, update_type = None, build_requires = 1, id_web=None, repository = [], prioryty = None):
        self.id_web=id_web
        self.project_name = project_name
        self.db = None
        self.arch = arch
        self.idbuild_list = None
        self.plname = plname
        self.bplname = None if bplname == "" else bplname
        self.idplatform = None
        self.idbuild_platform = None
        self.ready = None
        self.blist = None
        self.prioryty=prioryty
        self.circle = 0
        self.project_version = project_version
        self.build_requires = build_requires
        self.update_type = update_type
        self.repository=repository

    def check_platform(self):
        conn = DB_Pool().get_connection()

        self.idplatform = None

        try:
            res = conn.execute('select idplatform, ready from platform where (name = "' + self.plname + '")')
        finally:
            conn.close()

        if not res:
            self.ready = 1
            return 1

        self.idplatform = str(res[0]["idplatform"])

        if res[0]["ready"] == 0:
            self.ready = 2
            return 2

        return 0

    def check_build_platform(self):
        conn = DB_Pool().get_connection()

        self.idbuild_platform = None

        if self.bplname:
            res = conn.execute('select idplatform from platform where (name = "' + self.bplname + '")')

            if not res:
                return 1

            self.idbuild_platform = str(res[0]["idplatform"])

            #TODO

            conn.close()

        return 0


    def get_project_info(self):
        # idbuild_platform can be null for a basic platform, not for an user platform
        conn = DB_Pool().get_connection()

        if self.idbuild_platform:
            srpms_condition = ' = %s' % (self.idbuild_platform)
        else:
            srpms_condition = ' is null'

        try:
            res = conn.execute(sql_quieries['project_info'] % (self.project_name, srpms_condition, self.idplatform))
        finally:
            conn.close()

        if res:
            return res[0]
        else:
            return {'name' : self.project_name , 'version' : None}

    def get_rpm_requires(self):
        if self.check_platform() or self.check_build_platform():
            return []

        info = self.get_project_info()

        dep = {'name' : self.project_name,
               'version' : self.project_version if self.project_version else info['version']}

        out = {'0' : [dep]}

        self.get_tree(info['name'], False, out)

        req = []

        for level in out:
            for name in out[level]:
                req.append(name)

        return req

    def get_tree(self, srpm_name, reverse, out, level = 1, loop = []):
        # init the array if it's empty

        if not loop:
            loop = [srpm_name]

        names = self.get_requires(srpm_name, reverse)
        if not names:
            return 0

        circled = 0

        for row in names:
            if row["srpm_name"] in loop:
                if not circled:
                    circled = 0
                continue

            loop.append(row["srpm_name"])

            dep = {'name' : row["project_name"], 'version' : row["srpm_version"]}

            slevel = str(level)

            if slevel in out:
                out[slevel].append(dep)
            else:
                out.update({slevel : [dep]})

            res = self.get_tree(row["srpm_name"], reverse, out, level + 1, loop)
            
            if res:
                circled = res

        return circled

    def get_requires(self, srpm_name, reverse = True):
        # idbuild_platform can be null for a basic platform, not for an user platform

        conn = DB_Pool().get_connection()

        if self.idbuild_platform:
            srpms_condition = ' = %s' % (self.idbuild_platform)
        else:
            srpms_condition = ' is null'

        try:
            if reverse:
                res = conn.execute(sql_quieries["srpm_reverse"] % (self.idplatform, srpm_name, srpms_condition))

            else:
                res = conn.execute(sql_quieries["srpm_not_reverse"] %
                                      (sql_quieries["srpm_not_reverse_inner_join"] % (srpms_condition, srpm_name, self.idplatform) , 
                                      srpms_condition))
        finally:
            conn.close()

        return res

