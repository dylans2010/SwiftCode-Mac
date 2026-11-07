#ifndef _TVG_TASK_SCHEDULER_H_
#define _TVG_TASK_SCHEDULER_H_

#include "tvgCommon.h"
#include "tvgInlist.h"

#ifdef THORVG_THREAD_SUPPORT
    #include <atomic>
    #include <thread>
    #include <mutex>
    #include <condition_variable>
#endif

namespace tvg {

#ifdef THORVG_THREAD_SUPPORT

using ThreadID = std::thread::id;

struct Task
{
private:
    mutex                   mtx;
    condition_variable      cv;
    bool                    ready = true;
    bool                    pending = false;

public:
    INLIST_ITEM(Task);

    virtual ~Task() = default;

    void done()
    {
        if (!pending) return;

        unique_lock<mutex> lock(mtx);
        while (!ready) cv.wait(lock);
        pending = false;
    }

protected:
    virtual void run(unsigned tid) = 0;

private:
    void operator()(unsigned tid)
    {
        run(tid);

        lock_guard<mutex> lock(mtx);
        ready = true;
        cv.notify_one();
    }

    void prepare()
    {
        ready = false;
        pending = true;
    }

    friend struct TaskSchedulerImpl;
};

#else

using ThreadID = uint8_t;

struct Task
{
public:
    INLIST_ITEM(Task);

    virtual ~Task() = default;
    void done() {}

protected:
    virtual void run(unsigned tid) = 0;

private:
    friend struct TaskSchedulerImpl;
};

#endif

struct TaskScheduler
{
    static uint32_t threads();
    static void init(uint32_t threads);
    static void term();
    static void request(Task* task);
    static bool onthread();
    static ThreadID tid();
};

}

#endif
