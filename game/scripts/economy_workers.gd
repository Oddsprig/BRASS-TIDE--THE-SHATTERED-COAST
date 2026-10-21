extends RefCounted
## Disjoint copied harbors, bounded worker group, main-thread publication only.
const Economy=preload("res://scripts/economy.gd")
var group_id: int=-1
var jobs: Array=[]
var days: int=0
var started_us: int=0
var last_us: int=0
var last_workers: int=0

func start(ports: Array, count: int, blocked: Array, seed_value: int) -> void:
	assert(group_id<0)
	days=count
	jobs=[]
	for i in range(ports.size()):
		jobs.append({"port":ports[i].duplicate(true),"events":[],"seed":seed_value+i*7919,"blocked":blocked.duplicate()})
	started_us=Time.get_ticks_usec()
	last_workers=mini(jobs.size(),clampi(OS.get_processor_count()-2,1,8))
	if jobs.is_empty():return
	group_id=WorkerThreadPool.add_group_task(_work,jobs.size(),last_workers,false,"Brass Tide paid harbor production")

func _work(index: int) -> void:
	var job: Dictionary=jobs[index]
	var rng=RandomNumberGenerator.new()
	rng.seed=job.seed
	job.events=Economy.tick_ports([job.port],days,{"blockaded":job.blocked,"interport_trade":false,"rng":rng})

func ready() -> bool:
	return group_id<0 or WorkerThreadPool.is_group_task_completed(group_id)

func finish(force: bool=false) -> Dictionary:
	if not force and not ready():return {}
	if group_id>=0:WorkerThreadPool.wait_for_group_task_completion(group_id)
	group_id=-1
	var ports: Array=[]
	var messages: Array=[]
	for job in jobs:
		ports.append(job.port)
		messages.append_array(job.events)
	last_us=Time.get_ticks_usec()-started_us
	jobs=[]
	return {"ports":ports,"events":messages,"days":days,"workers":last_workers,"elapsedUs":last_us}
