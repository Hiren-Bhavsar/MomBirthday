import React,{useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {createClient} from '@supabase/supabase-js';
import {SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY} from './config';
import './styles.css';

const supabase=createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY);

function PublicQuiz(){
 const [questions,setQuestions]=useState([]),[settings,setSettings]=useState({title:'How Old Was Mom?',subtitle:'Walk around the room, find each numbered photo, and guess Mom\'s age.',show_score:true,show_leaderboard:false,require_all:true}),[leaderboard,setLeaderboard]=useState([]),[name,setName]=useState(''),[guesses,setGuesses]=useState({}),[status,setStatus]=useState(''),[loading,setLoading]=useState(true);
 useEffect(()=>{Promise.all([
   supabase.from('public_questions').select('id,number').order('number'),
   supabase.from('public_settings').select('title,subtitle,show_score,show_leaderboard,require_all').eq('id',1).maybeSingle()
 ]).then(([q,s])=>{setLoading(false);if(q.error)setStatus(q.error.message);else setQuestions(q.data||[]);if(s.data)setSettings(s.data);});},[]);
 async function submit(e){e.preventDefault();setStatus('');if(!name.trim())return setStatus('Please enter your name.');if(!questions.length)return setStatus('There are no photos set up yet.');
  const answers=questions.map(q=>({question_id:q.id,guess:guesses[q.id] === '' || guesses[q.id] == null ? null : Number(guesses[q.id])}));
  if(settings.require_all && answers.some(a=>!Number.isInteger(a.guess)||a.guess<0||a.guess>120))return setStatus('Please enter a whole-number age for every photo.');
  const cleanAnswers=answers.filter(a=>Number.isInteger(a.guess)&&a.guess>=0&&a.guess<=120);
  if(!cleanAnswers.length)return setStatus('Please enter at least one guess.');
  const {data,error}=await supabase.rpc('submit_quiz',{participant_name:name.trim(),answers:cleanAnswers});
  if(error)setStatus(error.message);else{setStatus(settings.show_score?`Submitted! You got ${data.correct} out of ${data.total} correct.`:'Submitted! Your guesses have been recorded.');setName('');setGuesses({});if(settings.show_leaderboard){const {data:lb}=await supabase.from('public_leaderboard').select('*').order('correct_count',{ascending:false}).order('submitted_at',{ascending:true});setLeaderboard(lb||[]);}}
 }
 return <main className="page"><section className="card hero"><div className="eyebrow">A birthday guessing game</div><h1>{settings.title}</h1><p>{settings.subtitle}</p></section><form className="card" onSubmit={submit}>
  <label className="nameLabel">Your name<input value={name} onChange={e=>setName(e.target.value)} placeholder="Enter your name" autoComplete="name"/></label>
  {loading?<p>Loading...</p>:<div className="questions">{questions.map(q=><label className="question" key={q.id}><span className="number">{q.number}</span><span>Mom was</span><input inputMode="numeric" type="number" min="0" max="120" value={guesses[q.id]??''} onChange={e=>setGuesses(g=>({...g,[q.id]:e.target.value}))} placeholder="Age"/><span>years old</span></label>)}</div>}
  <button disabled={loading}>{loading?'Loading…':'Submit My Guesses'}</button>{status&&<p className="status">{status}</p>}
 </form>{settings.show_leaderboard&&leaderboard.length>0&&<section className="card"><h2>Leaderboard</h2>{leaderboard.map((r,i)=><div className="resultRow" key={r.id}><strong>{i+1}</strong><span>{r.participant_name}</span><strong>{r.correct_count}/{r.total_questions}</strong></div>)}</section>}</main>
}

function Admin(){
 const [session,setSession]=useState(null),[email,setEmail]=useState(''),[password,setPassword]=useState(''),[questions,setQuestions]=useState([]),[results,setResults]=useState([]),[settings,setSettings]=useState({title:'How Old Was Mom?',subtitle:'Walk around the room, find each numbered photo, and guess Mom\'s age.',tolerance:0,show_score:true,show_leaderboard:false,require_all:true}),[status,setStatus]=useState('');
 useEffect(()=>{supabase.auth.getSession().then(({data})=>setSession(data.session));const {data}=supabase.auth.onAuthStateChange((_e,s)=>setSession(s));return()=>data.subscription.unsubscribe();},[]);
 useEffect(()=>{if(session)load();},[session]);
 async function login(e){e.preventDefault();setStatus('');const {error}=await supabase.auth.signInWithPassword({email,password});if(error)setStatus(error.message);}
 async function load(){const [q,r,s]=await Promise.all([
   supabase.from('questions').select('*').order('number'),
   supabase.from('submissions').select('id,participant_name,correct_count,total_questions,submitted_at').order('correct_count',{ascending:false}).order('submitted_at',{ascending:true}),
   supabase.from('quiz_settings').select('*').eq('id',1).maybeSingle()
 ]);if(q.error||r.error||s.error)setStatus((q.error||r.error||s.error).message);setQuestions(q.data||[]);setResults(r.data||[]);if(s.data)setSettings(s.data);}
 async function save(q){const {error}=await supabase.from('questions').update({number:Number(q.number),correct_age:Number(q.correct_age)}).eq('id',q.id);setStatus(error?error.message:'Saved.');load();}
 async function add(){const next=questions.length?Math.max(...questions.map(q=>Number(q.number)))+1:1;const {error}=await supabase.from('questions').insert({number:next,correct_age:0});if(error)setStatus(error.message);load();}
 async function remove(q){if(!confirm(`Delete photo #${q.number}?`))return;const {error}=await supabase.from('questions').delete().eq('id',q.id);setStatus(error?error.message:'Deleted.');load();}
 async function saveSettings(){const tolerance=Math.max(0,Math.min(120,Number(settings.tolerance)||0));const {error}=await supabase.from('quiz_settings').update({title:settings.title,subtitle:settings.subtitle,tolerance,show_score:settings.show_score,show_leaderboard:settings.show_leaderboard,require_all:settings.require_all}).eq('id',1);setStatus(error?error.message:'Quiz settings saved.');load();}
 if(!session)return <main className="page narrow"><form className="card login" onSubmit={login}><div className="eyebrow">Organizer only</div><h1>Admin Login</h1><p>This area is for the birthday quiz organizer.</p><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="Email" autoComplete="email"/><input type="password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="Password" autoComplete="current-password"/><button>Log in</button>{status&&<p className="status">{status}</p>}</form></main>;
 return <main className="page"><section className="card"><div className="adminHeader"><div><div className="eyebrow">KASHLondon</div><h1>Quiz Admin</h1></div><button className="secondary small" onClick={()=>supabase.auth.signOut()}>Log out</button></div>
  <h2>Quiz settings</h2><div className="settingsGrid"><label>Title<input value={settings.title} onChange={e=>setSettings(s=>({...s,title:e.target.value}))}/></label><label>Subtitle<input value={settings.subtitle} onChange={e=>setSettings(s=>({...s,subtitle:e.target.value}))}/></label><label>Acceptable age buffer (± years)<input type="number" min="0" max="120" value={settings.tolerance} onChange={e=>setSettings(s=>({...s,tolerance:e.target.value}))}/><span className="help">Any value from 0 to 120. For example, 3 means the guess can be three years above or below the correct age.</span></label><label className="checkLabel"><input type="checkbox" checked={settings.require_all} onChange={e=>setSettings(s=>({...s,require_all:e.target.checked}))}/> Require an answer for every photo</label><label className="checkLabel"><input type="checkbox" checked={settings.show_score} onChange={e=>setSettings(s=>({...s,show_score:e.target.checked}))}/> Show score immediately after submission</label><label className="checkLabel"><input type="checkbox" checked={settings.show_leaderboard} onChange={e=>setSettings(s=>({...s,show_leaderboard:e.target.checked}))}/> Show leaderboard publicly after submission</label></div><button className="secondary" onClick={saveSettings}>Save settings</button>
 </section><section className="card"><h2>Photo answers</h2><p>Enter the actual age Mom was in each printed photo.</p><div className="adminRows">{questions.map(q=><div className="adminRow" key={q.id}><label>Photo #<input type="number" value={q.number} onChange={e=>setQuestions(xs=>xs.map(x=>x.id===q.id?{...x,number:e.target.value}:x))}/></label><label>Correct age<input type="number" min="0" max="120" value={q.correct_age} onChange={e=>setQuestions(xs=>xs.map(x=>x.id===q.id?{...x,correct_age:e.target.value}:x))}/></label><button className="small" onClick={()=>save(q)}>Save</button><button className="secondary small" onClick={()=>remove(q)}>Delete</button></div>)}</div><button className="secondary" onClick={add}>+ Add photo</button>{status&&<p className="status">{status}</p>}</section>
 <section className="card"><h2>Leaderboard</h2>{results.length?<div>{results.map((r,i)=><div className="resultRow" key={r.id}><strong>{i+1}</strong><span>{r.participant_name}</span><strong>{r.correct_count}/{r.total_questions}</strong></div>)}</div>:<p>No submissions yet.</p>}</section></main>
}
function App(){return window.location.pathname.toLowerCase().includes('/kashlondon')?<Admin/>:<PublicQuiz/>}
createRoot(document.getElementById('root')).render(<App/>);
