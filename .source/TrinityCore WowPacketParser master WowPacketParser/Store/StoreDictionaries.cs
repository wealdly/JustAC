using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using WowPacketParser.Enums;
using WowPacketParser.Misc;
using WowPacketParser.SQL;

namespace WowPacketParser.Store
{
    public abstract class Store
    {
        public static UInt128 SQLEnabledFlags { protected get; set; }
        public List<SQLOutput> Types { get; protected set; }

        protected bool ProcessFlags()
        {
            return Types.Count == 0 ||
                Settings.DumpFormat == DumpFormatType.SniffDataOnly ||
                Types.Any(sqlOutput => SQLEnabledFlags.HasAnyFlagBit(sqlOutput));
        }

        public abstract void Clear();
        public abstract bool IsEmpty();

        protected bool Enabled;
    }

    public class StoreDictionary<T, TK> : Store, IEnumerable<KeyValuePair<T, Tuple<TK, TimeSpan?>>>
    {
        private readonly ConcurrentDictionary<T, Tuple<TK, TimeSpan?>> _dictionary;

        public StoreDictionary()
        {
            Types = new List<SQLOutput>();
            Enabled = true;
            _dictionary = new ConcurrentDictionary<T, Tuple<TK, TimeSpan?>>();
        }

        public StoreDictionary(List<SQLOutput> types)
        {
            Types = types;
            Enabled = ProcessFlags();
            _dictionary = Enabled ? new ConcurrentDictionary<T, Tuple<TK, TimeSpan?>>() : null;
        }

        public StoreDictionary(Dictionary<T, TK> dict)
        {
            _dictionary =
                new ConcurrentDictionary<T, Tuple<TK, TimeSpan?>>(dict.ToDictionary(pair => pair.Key,
                    pair => new Tuple<TK, TimeSpan?>(pair.Value, null)));
            Types = new List<SQLOutput>();
            Enabled = true;
        }

        public void Add(T key, TK value, TimeSpan? time = null)
        {
            if (!Enabled)
                return;

            if (_dictionary.ContainsKey(key))
                return;

            var newValue = new Tuple<TK, TimeSpan?>(value, time);
            _dictionary.AddOrUpdate(key, newValue, (k, oldval) =>
            {
                if (oldval.Item2.HasValue && time.HasValue && oldval.Item2.Value > time)
                    return oldval;
                return newValue;
            });
        }

        public bool Remove(T key)
        {
            Tuple<TK, TimeSpan?> t;
            return !Enabled || _dictionary.TryRemove(key, out t);
        }

        public bool ContainsKey(T key)
        {
            return Enabled && _dictionary.ContainsKey(key);
        }

        public bool TryGetValue(T key, out TK value)
        {
            if (key == null)
            {
                value = default(TK);
                return false;
            }

            if (Enabled)
            {
                Tuple<TK, TimeSpan?> tuple;
                if (_dictionary.TryGetValue(key, out tuple))
                {
                    value = tuple.Item1;
                    return true;
                }
            }

            value = default(TK);
            return false;
        }

        public bool TryGetValue(T key, out Tuple<TK, TimeSpan?> value)
        {
            if (key == null)
            {
                value = null;
                return false;
            }

            if (Enabled)
                return _dictionary.TryGetValue(key, out value);
            value = null;
            return false;
        }

        public Tuple<TK, TimeSpan?> this[T key]
        {
            get
            {
                return Enabled ? _dictionary[key] : null;
            }
            set
            {
                if (Enabled)
                    _dictionary[key] = value;
            }
        }

        public override void Clear()
        {
            if (Enabled)
                _dictionary.Clear();
        }

        public override bool IsEmpty()
        {
            return !Enabled || _dictionary.Count == 0;
        }

        public IEnumerator<KeyValuePair<T, Tuple<TK, TimeSpan?>>> GetEnumerator()
        {
            return Enabled ? _dictionary.GetEnumerator() : new Dictionary<T, Tuple<TK, TimeSpan?>>().GetEnumerator();
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return GetEnumerator();
        }

        public ICollection<T> Keys
        {
            get
            {
                return Enabled ? _dictionary.Keys : new List<T>();
            }
        }

        public ICollection<Tuple<TK, TimeSpan?>> Values
        {
            get
            {
                return Enabled ? _dictionary.Values : new List<Tuple<TK, TimeSpan?>>();
            }
        }
    }

    public class StoreMulti<T, TK> : Store, IEnumerable<KeyValuePair<T, ICollection<Tuple<TK, TimeSpan?>>>>
    {
        private readonly ConcurrentDictionary<T, ICollection<Tuple<TK, TimeSpan?>>> _dictionary;

        public StoreMulti()
        {
            Types = [];
            Enabled = true;
            _dictionary = new ConcurrentDictionary<T, ICollection<Tuple<TK, TimeSpan?>>>();
        }

        public StoreMulti(List<SQLOutput> types)
        {
            Types = types;
            Enabled = ProcessFlags();
            _dictionary = Enabled ? new ConcurrentDictionary<T, ICollection<Tuple<TK, TimeSpan?>>>() : null;
        }

        public StoreMulti(Dictionary<T, ICollection<TK>> dict)
        {
            _dictionary =
                new ConcurrentDictionary<T, ICollection<Tuple<TK, TimeSpan?>>>(dict.ToDictionary(pair => pair.Key,
                    ICollection<Tuple<TK, TimeSpan?>> (pair) => pair.Value.Select(value => new Tuple<TK, TimeSpan?>(value, null)).ToList()));
            Types = [];
            Enabled = true;
        }

        public void Add(T key, TK value, TimeSpan? time = null)
        {
            if (!Enabled)
                return;

            var newValue = new Tuple<TK, TimeSpan?>(value, time);
            _dictionary.AddOrUpdate(key, _ => [newValue], (k, oldval) =>
            {
                oldval.Add(newValue);
                return oldval;
            });
        }

        public bool Remove(T key)
        {
            return !Enabled || _dictionary.TryRemove(key, out _);
        }

        public bool ContainsKey(T key)
        {
            return Enabled && _dictionary.ContainsKey(key);
        }

        public ICollection<Tuple<TK, TimeSpan?>> this[T key]
        {
            get => Enabled ? _dictionary[key] : null;
            set
            {
                if (Enabled)
                    _dictionary[key] = value;
            }
        }

        public override void Clear()
        {
            if (Enabled)
                _dictionary.Clear();
        }

        public override bool IsEmpty() => !Enabled || _dictionary.IsEmpty;

        public IEnumerator<KeyValuePair<T, ICollection<Tuple<TK, TimeSpan?>>>> GetEnumerator()
        {
            return Enabled ? _dictionary.GetEnumerator() : new Dictionary<T, ICollection<Tuple<TK, TimeSpan?>>>().GetEnumerator();
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return GetEnumerator();
        }

        public ICollection<T> Keys => Enabled ? _dictionary.Keys : new List<T>();

        public ICollection<ICollection<Tuple<TK, TimeSpan?>>> Values => Enabled ? _dictionary.Values : [];
    }

    public class StoreBag<T> : Store, IEnumerable<Tuple<T, TimeSpan?>>
    {
        protected readonly ConcurrentBag<Tuple<T, TimeSpan?>> Bag;

        public StoreBag()
        {
            Types = new List<SQLOutput>();
            Enabled = true;
            Bag = new ConcurrentBag<Tuple<T, TimeSpan?>>();
        }

        public StoreBag(List<SQLOutput> types)
        {
            Types = types;
            Enabled = ProcessFlags();
            Bag = Enabled ? new ConcurrentBag<Tuple<T, TimeSpan?>>() : null;
        }

        public void Add(T item, TimeSpan? time = null)
        {
            if (Enabled)
                Bag.Add(new Tuple<T, TimeSpan?>(item, time));
        }

        public override void Clear()
        {
            if (Enabled)
            {
                while (Bag.Count > 0)
                {
                    Tuple<T, TimeSpan?> t;
                    Bag.TryTake(out t);
                }
            }
        }

        public override bool IsEmpty()
        {
            return !Enabled || Bag.Count == 0;
        }

        public IEnumerator<Tuple<T, TimeSpan?>> GetEnumerator()
        {
            return Enabled ? Bag.GetEnumerator() : new List<Tuple<T, TimeSpan?>>().GetEnumerator();
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return GetEnumerator();
        }
    }

    public class DataBag<T> : StoreBag<T> where T : IDataModel
    {
        public DataBag() { }

        public DataBag(List<SQLOutput> types) : base(types) { }

        public Tuple<T, TimeSpan?> this[T key]
        {
            get
            {
                if (!Enabled) return null;
                return Bag.FirstOrDefault(c => SQLUtil.GetFields<T>()
                    .Where(f => f.Item3.Any(g => g.IsPrimaryKey))
                    .All(f => (f.Item2.GetValue(c.Item1).Equals(f.Item2.GetValue(key)))));
            }
        }

        public bool ContainsKey(T key)
        {
            return Enabled && Bag.Any(
                c =>
                    SQLUtil.GetFields<T>()
                        .Where(f => f.Item3.Any(g => g.IsPrimaryKey))
                        .All(f => (f.Item2.GetValue(c.Item1).Equals(f.Item2.GetValue(key)))));
        }

        public bool Contains(T key)
        {
            return Enabled && Bag.Any(
                c => SQLUtil.GetFields<T>()
                .Where(f => f.Item2.GetValue(key) != null)
                .All(f => (f.Item2.GetValue(c.Item1).Equals(f.Item2.GetValue(key)))));
        }
    }
}
