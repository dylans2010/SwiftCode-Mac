#include "tvgSwCommon.h"

static thread_local SwMpool* _pool = nullptr;
static Array<SwMpool*> _pools;
static uint32_t _threads = 0;
static StrictKey _key;

SwMpool* mpoolReq()
{
    if (!_pool) {
        _pool = new SwMpool(_threads);
        ScopedLock lock(_key);
        _pools.push(_pool);
    }
    return _pool;
}

void mpoolInit(uint32_t threads)
{
    _threads = threads;
}

void mpoolTerm()
{
    for (auto p : _pools) {
        delete p;
        _pool = nullptr;
    }
    _pools.reset();
}
