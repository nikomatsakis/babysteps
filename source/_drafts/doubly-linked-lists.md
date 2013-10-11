And now for something completely different. Over in Rust land, we've
been discussing the right semantics of failure. As part of that
discussion, I was thinking about how we could maintain a tree of
parallel tasks very cheaply.

My basic thought was to represent the task tree using a Knuth-ian
representation, in which a tree node looks like:

```C
struct TaskTree {
    TaskTree *child;
    TaskTree *sibling;
}
```

Now, if you want to visit the children of a node, you first descend
the `child` link and then follow all the `sibling` links. Basically
each node has a linked list of its children.

Now, it's well-known how one can implement a linked list with
fine-grained locking for parallel insertion and removal. However, the
algorithms I've seen are all concerned with singly linked lists, and
removal from a singly linked list is O(n) in the number of children,
which is clearly unacceptable.

The problem is that extending these algorithms to doubly linked lists
is tricky because you run the risk of deadlock. To see why, consider
the case where both a node N and its predecessor M are being removed
from the list at the same time. Let's consider the node N first. The
naive algorithm would first lock the node N, read its prececessor M
and successor O, lock the predecessor and successor, then adust all
the fields as necessary. But this algorithm can clearly deadlock if
the predecessor M is also removing itself at the same time (N acquires
a lock on N, M acquires a lock on M, N tries to acquire a lock on M, M
tries to acquire a lock on N, bang!). In a singly linked list
scenario, you avoid this problem by always locking the head of the
list first and proceeding down the list.

My plan to avoid this problem is as follows. First, for reference,
imagine that our node is defined:

```C
struct Node {
    Node *next;
    Node *prev;
}
```

The algorithm for removal is:

```C
Node Sentinel;

void remove(Node *node) {
    while (true) {
        Node *prev = &Sentinel;
        exchange(&node->prev, &prev);
        if (prev == &Sentinel) {
        }

    exchange(&node->next, &next);
    if (prev == &Sentinel) {
    }
}
```

