from cpython.mem cimport PyMem_Free, PyMem_Malloc
from cpython.exc cimport PyErr_CheckSignals

from libc.stdio cimport FILE, fopen, fclose, fread, fwrite, feof, fseek
from libc.errno cimport errno
from libc.stdio cimport FILE, fopen, fclose, fread, fwrite, feof, fseek
from libc.errno cimport errno
from libc.string cimport memcpy
from libc.string cimport memset

from libc.stdlib cimport qsort
from libc.stdint cimport int32_t

from preshed.maps cimport PreshMap, MapStruct, map_get
from .sparse cimport SparseArray

from ..extra.eg cimport Example
from ..structs cimport SparseArrayC
from ..typedefs cimport class_t, count_t, feat_t

from os import path


cdef class Writer:
    def __init__(self, object loc, nr_class):
        if path.exists(loc):
            assert not path.isdir(loc)
        cdef bytes bytes_loc = loc.encode('utf8') if type(loc) == unicode else loc
        self._fp = fopen(<char*>bytes_loc, 'wb')
        assert self._fp != NULL
        fseek(self._fp, 0, 0)
        self._nr_class = nr_class
        _write(&self._nr_class, sizeof(self._nr_class), 1, self._fp)

    def close(self):
        cdef size_t status = fclose(self._fp)
        assert status == 0

    cdef int write(self, feat_t feat_id, SparseArrayC* feat) except -1:
        if feat == NULL:
            return 0
        
        _write(&feat_id, sizeof(feat_id), 1, self._fp)
        
        cdef int i = 0
        while feat[i].key >= 0:
            i += 1
        cdef int32_t length = i
        
        _write(&length, sizeof(length), 1, self._fp)
        
        qsort(feat, length, sizeof(SparseArrayC), SparseArray.cmp)
        
        for i in range(length):
            _write(&feat[i].key, sizeof(feat[i].key), 1, self._fp)
            _write(&feat[i].val, sizeof(feat[i].val), 1, self._fp)


cdef int _write(void* value, size_t size, int n, FILE* fp) except -1:
    status = fwrite(value, size, 1, fp)
    assert status == 1, status


cdef class Reader:
    def __init__(self, loc):
        assert path.exists(loc)
        assert not path.isdir(loc)
        cdef bytes bytes_loc = loc.encode('utf8') if type(loc) == unicode else loc
        self._fp = fopen(<char*>bytes_loc, 'rb')
        assert self._fp != NULL
        status = fseek(self._fp, 0, 0)
        status = fread(&self._nr_class, sizeof(self._nr_class), 1, self._fp)

    def __dealloc__(self):
        fclose(self._fp)

    cdef int read(self, Pool mem, feat_t* out_id, SparseArrayC** out_feat) except -1:
        cdef feat_t feat_id
        cdef int32_t length

        status = fread(&feat_id, sizeof(feat_t), 1, self._fp)
        if status == 0:
            return 0
        assert status

        status = fread(&length, sizeof(length), 1, self._fp)
        assert status
        
        feat = <SparseArrayC*>PyMem_Malloc((length + 1) * sizeof(SparseArrayC))
        
        cdef int i
        for i in range(length):
            status = fread(&feat[i].key, sizeof(feat[i].key), 1, self._fp)
            assert status
            status = fread(&feat[i].val, sizeof(feat[i].val), 1, self._fp)
            assert status

        # Trust We allocated correctly above
        feat[length].key = -2 # Indicates end of memory region
        feat[length].val = 0

        # Copy into the output variables
        out_feat[0] = feat
        out_id[0] = feat_id
        # Signal whether to continue reading, to the outer loop
        if feof(self._fp):
            return 0
        else:
            return 1
