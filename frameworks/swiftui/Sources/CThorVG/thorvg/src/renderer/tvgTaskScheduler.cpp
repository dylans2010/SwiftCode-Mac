#include "tvgArray.h"
#include "tvgInlist.h"
#include "tvgTaskScheduler.h"

namespace tvg {

#ifdef THORVG_THREAD_SUPPORT

struct TaskQueue {
    Inlist<Task>             taskDeque;
    mutex                    mtx;
    condition_variable       ready;
    bool                     done = false;

    bool tryPop(Task** task)
    {
        unique_lock<mutex> lock{mtx, try_to_lock};
        if (!lock || taskDeque.empty()) return false;
        *task = taskDeque.front();
        return true;
    }

    bool tryPush(Task* task)
    {
        {
            unique_lock<mutex> lock{mtx, try_to_lock};
            if (!lock) return false;
            taskDeque.back(task);
        }
        ready.notify_one();
        return true;
    }

    void complete()
    {
        {
            lock_guard<mutex> lock{mtx};
            done = true;
        }
        ready.notify_all();
    }

    bool pop(Task** task)
    {
        unique_lock<mutex> lock{mtx};

        while (taskDeque.empty() && !done) {
            ready.wait(lock);
        }

        if (taskDeque.empty()) return false;

        *task = taskDeque.front();
        return true;
    }

    void push(Task* task)
    {
        {
            lock_guard<mutex> lock{mtx};
            taskDeque.back(task);
        }
        ready.notify_one();
    }
};

struct TaskSchedulerImpl
{
    Array<thread*>                 threads;
    Array<TaskQueue*>              taskQueues;
    atomic<uint32_t>               idx{0};

    TaskSchedulerImpl(uint32_t threadCnt)
    {
        threads.reserve(threadCnt);
        taskQueues.reserve(threadCnt);

        for (uint32_t i = 0; i < threadCnt; ++i) {
            taskQueues.push(new TaskQueue);
            threads.push(new thread);
        }
        for (uint32_t i = 0; i < threadCnt; ++i) {
            *threads.data[i] = thread([&, i] { run(i); });
        }
    }

    ~TaskSchedulerImpl()
    {
        ARRAY_FOREACH(p, taskQueues) {
            (*p)->complete();
        }
        ARRAY_FOREACH(p, threads) {
            (*p)->join();
            delete(*p);
        }
        ARRAY_FOREACH(p, taskQueues) {
            delete(*p);
        }
    }

    void run(unsigned i)
    {
        Task* task;

        while (true) {
            auto success = false;
            for (uint32_t x = 0; x < threads.count * 2; ++x) {
                if (taskQueues[(i + x) % threads.count]->tryPop(&task)) {
                    success = true;
                    break;
                }
            }

            if (!success && !taskQueues[i]->pop(&task)) break;
            (*task)(i + 1);
        }
    }

    void request(Task* task)
    {
        if (threads.count > 0) {
            task->prepare();
            auto i = idx++;
            for (uint32_t n = 0; n < threads.count; ++n) {
                if (taskQueues[(i + n) % threads.count]->tryPush(task)) return;
            }
            taskQueues[i % threads.count]->push(task);
        } else {
            task->run(0);
        }
    }

    uint32_t threadCnt()
    {
        return threads.count;
    }
};

#else

struct TaskSchedulerImpl
{
    TaskSchedulerImpl(TVG_UNUSED uint32_t threadCnt) {}
    void request(Task* task) { task->run(0); }
    uint32_t threadCnt() { return 0; }
};

#endif

}

static TaskSchedulerImpl* _inst = nullptr;
static ThreadID _tid;

void TaskScheduler::init(uint32_t threads)
{
    if (_inst) return;
    _inst = new TaskSchedulerImpl(threads);
    _tid = tid();
}

void TaskScheduler::term()
{
    delete(_inst);
    _inst = nullptr;
}

void TaskScheduler::request(Task* task)
{
    if (_inst) _inst->request(task);
}

uint32_t TaskScheduler::threads()
{
    return _inst ? _inst->threadCnt() : 0;
}

bool TaskScheduler::onthread()
{
    return _tid != tid();
}

ThreadID TaskScheduler::tid()
{
#ifdef THORVG_THREAD_SUPPORT
    return std::this_thread::get_id();
#else
    return 0;
#endif
}
