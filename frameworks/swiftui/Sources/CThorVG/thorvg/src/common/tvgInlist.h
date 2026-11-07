#ifndef _TVG_INLIST_H_
#define _TVG_INLIST_H_

#include <cstdint>

namespace tvg
{

#define INLIST_ITEM(T) \
    T* prev; \
    T* next

template<typename T>
struct Inlist
{
    T* head = nullptr;
    T* tail = nullptr;
    uint32_t count = 0;

    ~Inlist()
    {
        free();
    }

    void free()
    {
        while (head) {
            auto t = head;
            head = t->next;
            delete(t);
        }
        head = tail = nullptr;
        count = 0;
    }

    void back(T* element)
    {
        if (tail) {
            tail->next = element;
            element->prev = tail;
            element->next = nullptr;
            tail = element;
        } else {
            head = tail = element;
            element->prev = nullptr;
            element->next = nullptr;
        }
        ++count;
    }

    void front(T* element)
    {
        if (head) {
            head->prev = element;
            element->prev = nullptr;
            element->next = head;
            head = element;
        } else {
            head = tail = element;
            element->prev = nullptr;
            element->next = nullptr;
        }
        ++count;
    }

    T* back()
    {
        if (!tail) return nullptr;
        --count;
        auto t = tail;
        tail = t->prev;
        if (!tail) head = nullptr;
        return t;
    }

    T* front()
    {
        if (!head) return nullptr;
        --count;
        auto t = head;
        head = t->next;
        if (!head) tail = nullptr;
        return t;
    }

    void remove(T* element)
    {
        if (element->prev) element->prev->next = element->next;
        if (element->next) element->next->prev = element->prev;
        if (element == head) head = element->next;
        if (element == tail) tail = element->prev;
        element->prev = element->next = nullptr;
        --count;
    }

    bool empty() const
    {
        return head ? false : true;
    }
};

#define INLIST_FOREACH(inlist, cur) \
    for (auto cur = inlist.head; cur; cur = cur->next)

#define INLIST_SAFE_FOREACH(inlist, cur) \
    auto cur = inlist.head; \
    auto next = cur ? cur->next : nullptr; \
    for (; cur; cur = next, next = (cur ? cur->next : nullptr))

}

#endif
